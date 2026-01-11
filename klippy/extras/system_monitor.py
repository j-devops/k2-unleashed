# Complete System Status Monitor for K2 Series
#
# Copyright (C) 2025 K2 Unleashed Contributors
#
# This file is part of K2 Unleashed.
#
# K2 Unleashed is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# K2 Unleashed is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with K2 Unleashed.  If not, see <https://www.gnu.org/licenses/>.

import time
import logging
import json
import os
from collections import deque

class SystemMonitor:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.reactor = self.printer.get_reactor()
        self.gcode = self.printer.lookup_object('gcode')

        # Error and state history
        self.error_history = deque(maxlen=500)
        self.state_history = deque(maxlen=100)
        self.last_status = {}

        # Cached status for non-blocking queries
        self.cached_state = {}
        self.cached_motion = {}
        self.cached_thermal = {}
        self.cached_sensors = {}
        self.cached_cfs = {}
        self.cached_resources = {}
        self.cache_timestamp = 0
        self.cache_max_age = 2.0  # Use cached data if less than 2 seconds old

        # Configuration
        self.update_interval = config.getfloat('update_interval', 0.5, above=0.1)
        self.persist_errors = config.getboolean('persist_errors', True)
        self.error_log_path = config.get('error_log_path',
                                         '/usr/data/printer_data/logs/system_errors.jsonl')

        # Safe query mode - use cached data during sensitive operations
        self.safe_query_mode = config.getboolean('safe_query_mode', True)

        # Register event handlers
        self.printer.register_event_handler("klippy:ready", self._handle_ready)
        self.printer.register_event_handler("klippy:shutdown", self._handle_shutdown)
        self.printer.register_event_handler("klippy:disconnect", self._handle_disconnect)

        # Register homing/probing event handlers to avoid queries during critical operations
        self.printer.register_event_handler("homing:homing_move_begin",
                                           self._handle_homing_begin)
        self.printer.register_event_handler("homing:homing_move_end",
                                           self._handle_homing_end)

        # Register webhooks for API access
        webhooks = self.printer.lookup_object('webhooks')
        webhooks.register_endpoint("system_monitor/status",
                                   self._handle_status_request)
        webhooks.register_endpoint("system_monitor/errors",
                                   self._handle_errors_request)
        webhooks.register_endpoint("system_monitor/log_error",
                                   self._handle_log_error_request)
        webhooks.register_endpoint("system_monitor/clear_errors",
                                   self._handle_clear_errors_request)

        # Register G-code commands
        self.gcode.register_command("SYSTEM_STATUS", self.cmd_SYSTEM_STATUS,
                                   desc=self.cmd_SYSTEM_STATUS_help)
        self.gcode.register_command("LOG_ERROR", self.cmd_LOG_ERROR,
                                   desc=self.cmd_LOG_ERROR_help)
        self.gcode.register_command("SHOW_ERRORS", self.cmd_SHOW_ERRORS,
                                   desc=self.cmd_SHOW_ERRORS_help)
        self.gcode.register_command("DEBUG_HOMING", self.cmd_DEBUG_HOMING,
                                   desc=self.cmd_DEBUG_HOMING_help)

        # Cached object references (populated in _handle_ready)
        self.print_stats = None
        self.pause_resume = None
        self.toolhead = None
        self.gcode_move = None

        # Critical operation tracking
        self.is_homing = False
        self.is_probing = False

        logging.info("SystemMonitor initialized")

    def _handle_ready(self):
        """Called when Klipper is ready"""
        # Cache references to commonly used objects
        self.print_stats = self.printer.lookup_object('print_stats', None)
        self.pause_resume = self.printer.lookup_object('pause_resume', None)
        self.toolhead = self.printer.lookup_object('toolhead', None)
        self.gcode_move = self.printer.lookup_object('gcode_move', None)

        logging.info("SystemMonitor ready")
        self.log_event("INFO", "I000", "System monitor started")

    def _handle_shutdown(self):
        """Called on Klipper shutdown"""
        self.log_event("WARNING", "W999", "System shutting down")

    def _handle_disconnect(self):
        """Called on MCU disconnect"""
        self.log_event("ERROR", "E401", "MCU communication lost")

    def _handle_homing_begin(self, homing_state):
        """Called when homing/probing begins - CRITICAL: avoid all queries"""
        self.is_homing = True
        logging.debug("SystemMonitor: Homing started - switching to cache-only mode")

    def _handle_homing_end(self, homing_state):
        """Called when homing/probing ends"""
        self.is_homing = False
        logging.debug("SystemMonitor: Homing completed - resuming normal queries")

    # Error and Event Logging

    def log_event(self, severity, code, message, context=None):
        """
        Log an error or event
        severity: "INFO", "WARNING", "ERROR", "CRITICAL"
        code: Error code (e.g., "E102")
        message: Human-readable message
        context: Dict with additional context
        """
        event = {
            "timestamp": time.time(),
            "severity": severity,
            "code": code,
            "message": message,
            "context": context or {},
            "state": self._get_current_state()
        }

        self.error_history.append(event)

        # Log to console
        log_func = {
            "INFO": logging.info,
            "WARNING": logging.warning,
            "ERROR": logging.error,
            "CRITICAL": logging.critical
        }.get(severity, logging.info)

        log_func("[%s] %s: %s" % (code, severity, message))

        # Persist to file
        if self.persist_errors and severity in ["ERROR", "CRITICAL"]:
            self._persist_error(event)

        return event

    def _persist_error(self, event):
        """Write error to log file (JSONL format)"""
        try:
            os.makedirs(os.path.dirname(self.error_log_path), exist_ok=True)
            with open(self.error_log_path, 'a') as f:
                f.write(json.dumps(event) + '\n')
        except Exception as e:
            logging.error("Failed to persist error: %s" % str(e))

    # Status Aggregation

    def _is_printing(self):
        """Check if printer is actively printing"""
        if self.print_stats:
            try:
                eventtime = self.reactor.monotonic()
                status = self.print_stats.get_status(eventtime)
                state = status.get('state', 'unknown')
                return state == "printing"
            except:
                return False
        return False

    def _in_critical_operation(self):
        """Check if printer is in a timing-sensitive operation"""
        # CRITICAL: During homing, any queries can disrupt timing and crash the head
        if self.is_homing or self.is_probing:
            return True

        # Also avoid queries during printing
        if self._is_printing():
            return True

        return False

    def _should_use_cache(self, eventtime):
        """Determine if we should use cached data to avoid blocking"""
        if not self.safe_query_mode:
            return False

        # Use cache if we're in critical operation (homing, probing, printing)
        if self._in_critical_operation():
            return True

        # Use cache if it's recent enough
        cache_age = eventtime - self.cache_timestamp
        if cache_age < self.cache_max_age:
            return True

        return False

    def _get_current_state(self):
        """Get basic current state"""
        if self.print_stats:
            try:
                eventtime = self.reactor.monotonic()
                status = self.print_stats.get_status(eventtime)
                return status.get('state', 'unknown')
            except:
                return "unknown"
        return "unknown"

    def aggregate_status(self, eventtime=None):
        """Aggregate complete system status"""
        if eventtime is None:
            eventtime = self.reactor.monotonic()

        # Check if we should use cached data to avoid blocking
        use_cache = self._should_use_cache(eventtime)

        if use_cache and self.cache_timestamp > 0:
            # Log why we're using cache (helps diagnose timing issues)
            if self.is_homing:
                logging.info("SystemMonitor: Using cached data during homing (protecting timing)")
            elif self.is_probing:
                logging.info("SystemMonitor: Using cached data during probing (protecting timing)")
            elif self._is_printing():
                logging.debug("SystemMonitor: Using cached data during printing")

            # Return cached status to avoid interfering with print timing
            status = {
                "timestamp": eventtime,
                "state": self.cached_state,
                "motion": self.cached_motion,
                "thermal": self.cached_thermal,
                "sensors": self.cached_sensors,
                "cfs": self.cached_cfs,
                "resources": self.cached_resources,
                "cached": True,
                "cache_age": eventtime - self.cache_timestamp,
                "homing": self.is_homing,
                "probing": self.is_probing
            }
        else:
            # Safe to query - update cache
            status = {
                "timestamp": eventtime,
                "state": self._get_state_status(eventtime),
                "motion": self._get_motion_status(eventtime),
                "thermal": self._get_thermal_status(eventtime),
                "sensors": self._get_sensor_status(eventtime),
                "cfs": self._get_cfs_status(eventtime),
                "resources": self._get_resource_status(eventtime),
                "cached": False
            }

            # Update cache
            self.cached_state = status["state"]
            self.cached_motion = status["motion"]
            self.cached_thermal = status["thermal"]
            self.cached_sensors = status["sensors"]
            self.cached_cfs = status["cfs"]
            self.cached_resources = status["resources"]
            self.cache_timestamp = eventtime

        self.last_status = status
        return status

    def _get_state_status(self, eventtime):
        """Get printer state"""
        state = {
            "current": "unknown",
            "homed_axes": [],
            "print_progress": 0,
            "is_paused": False
        }

        if self.print_stats:
            ps = self.print_stats.get_status(eventtime)
            state["current"] = ps.get("state", "unknown")
            state["print_progress"] = self._calculate_progress(ps)

        if self.pause_resume:
            state["is_paused"] = self.pause_resume.is_paused

        if self.toolhead:
            homed = self.toolhead.get_status(eventtime).get("homed_axes", "")
            state["homed_axes"] = list(homed)

        return state

    def _calculate_progress(self, print_stats):
        """Calculate print progress percentage"""
        # This is a simplified calculation
        # In reality, you'd want to use file position from virtual_sdcard
        total_duration = print_stats.get("total_duration", 0)
        if total_duration > 0:
            # Placeholder - should integrate with virtual_sdcard
            return min(total_duration / 100.0, 100.0)
        return 0

    def _get_motion_status(self, eventtime):
        """Get motion system status (non-blocking)"""
        motion = {
            "position": {"x": 0, "y": 0, "z": 0, "e": 0},
            "velocity": {"current": 0, "max": 0},
            "acceleration": {"current": 0, "max": 0},
            "homed": False
        }

        # Toolhead queries - wrapped to avoid blocking during moves
        if self.toolhead:
            try:
                th = self.toolhead.get_status(eventtime)
                pos = th.get("position", [0, 0, 0, 0])
                motion["position"] = {
                    "x": round(pos[0], 2),
                    "y": round(pos[1], 2),
                    "z": round(pos[2], 2),
                    "e": round(pos[3], 2)
                }
                motion["velocity"]["max"] = th.get("max_velocity", 0)
                motion["acceleration"]["max"] = th.get("max_accel", 0)
                motion["homed"] = len(th.get("homed_axes", "")) == 3
            except Exception as e:
                # Failed to query motion - use cached if available
                if self.cached_motion:
                    return self.cached_motion
                logging.debug("Motion status query failed (likely during move): %s" % str(e))

        # GCode move queries - less critical but still wrap
        if self.gcode_move:
            try:
                gm = self.gcode_move.get_status(eventtime)
                motion["velocity"]["current"] = gm.get("speed", 0)
                motion["acceleration"]["current"] = gm.get("accel", 0)
            except Exception as e:
                logging.debug("GCode move status query failed: %s" % str(e))

        return motion

    def _get_thermal_status(self, eventtime):
        """Get thermal system status (non-blocking)"""
        thermal = {}

        # Get all heaters - wrapped for safety
        try:
            heaters = self.printer.lookup_object('heaters', None)
            if heaters:
                for heater_name in ['extruder', 'heater_bed', 'chamber_heater']:
                    try:
                        heater = self.printer.lookup_object(heater_name, None)
                        if heater:
                            h_status = heater.get_status(eventtime)
                            thermal[heater_name] = {
                                "current": round(h_status.get("temperature", 0), 1),
                                "target": round(h_status.get("target", 0), 1),
                                "power": round(h_status.get("power", 0) * 100, 1)
                            }
                    except Exception as e:
                        logging.debug("Failed to query heater %s: %s" % (heater_name, str(e)))
        except Exception as e:
            # Failed to query heaters - use cached if available
            if self.cached_thermal:
                return self.cached_thermal
            logging.debug("Thermal status query failed: %s" % str(e))

        return thermal

    def _get_sensor_status(self, eventtime):
        """Get sensor status (non-blocking)"""
        sensors = {}

        # Filament sensor
        try:
            filament = self.printer.lookup_object('filament_switch_sensor filament_sensor', None)
            if filament:
                f_status = filament.get_status(eventtime)
                sensors["filament_sensor"] = {
                    "triggered": f_status.get("filament_detected", False),
                    "enabled": f_status.get("enabled", False)
                }
        except Exception as e:
            logging.debug("Filament sensor query failed: %s" % str(e))

        # Probe - Skip to avoid interfering with PRTouch during bed mesh
        # The PRTouch system doesn't like being queried during calibration
        # sensors["probe"] is intentionally omitted to prevent conflicts

        # Fans - wrap each query individually
        sensors["fans"] = {}
        for fan_name in ['fan0', 'fan1', 'fan2']:
            try:
                fan = self.printer.lookup_object('output_pin ' + fan_name, None)
                if fan:
                    f_status = fan.get_status(eventtime)
                    sensors["fans"][fan_name] = {
                        "speed": int(f_status.get("value", 0) * 255)
                    }
            except Exception as e:
                logging.debug("Fan %s query failed: %s" % (fan_name, str(e)))

        return sensors

    def _get_cfs_status(self, eventtime):
        """Get CFS (multi-color box) status (non-blocking)"""
        cfs = {
            "connected": False,
            "active_material": None,
            "materials": [],
            "buffer_level": 0
        }

        try:
            box = self.printer.lookup_object('box', None)
            if box:
                box_status = box.get_status(eventtime)
                cfs["connected"] = True
                # Note: Actual fields depend on box_wrapper implementation
                # which is proprietary. This is a placeholder.
                cfs["active_material"] = box_status.get("current_material", None)
        except Exception as e:
            logging.debug("CFS status query failed: %s" % str(e))

        return cfs

    def _get_resource_status(self, eventtime):
        """Get system resource usage (non-blocking)"""
        resources = {
            "cpu_usage": 0,
            "memory_usage": 0,
            "mcu_load": 0,
            "uptime": 0
        }

        # System stats - can be slow
        try:
            system_stats = self.printer.lookup_object('system_stats', None)
            if system_stats:
                stats = system_stats.get_status(eventtime)
                resources["cpu_usage"] = round(stats.get("cputime", 0), 1)
                resources["uptime"] = stats.get("sysload", 0)
        except Exception as e:
            logging.debug("System stats query failed: %s" % str(e))

        # MCU stats - critical not to interfere
        try:
            mcu = self.printer.lookup_object('mcu', None)
            if mcu:
                mcu_stats = mcu.get_status(eventtime)
                resources["mcu_load"] = round(mcu_stats.get("mcu_awake", 0) * 100, 1)
        except Exception as e:
            logging.debug("MCU stats query failed: %s" % str(e))

        return resources

    # Webhook Handlers

    def _handle_status_request(self, web_request):
        """API endpoint: Get current system status"""
        eventtime = self.reactor.monotonic()
        status = self.aggregate_status(eventtime)
        web_request.send(status)
        return status

    def _handle_errors_request(self, web_request):
        """API endpoint: Get error history"""
        params = web_request.get_args()
        limit = int(params.get('limit', 50))
        offset = int(params.get('offset', 0))
        severity = params.get('severity', None)

        # Filter errors
        errors = list(self.error_history)
        if severity:
            errors = [e for e in errors if e['severity'] == severity]

        total = len(errors)
        errors = errors[offset:offset + limit]

        result = {
            "errors": errors,
            "total": total,
            "has_more": offset + limit < total
        }

        web_request.send(result)
        return result

    def _handle_log_error_request(self, web_request):
        """API endpoint: Log a custom error"""
        params = web_request.get_args()
        severity = params.get('severity', 'ERROR')
        code = params.get('code', 'U000')
        message = params.get('message', 'Unknown error')
        context = params.get('context', {})

        event = self.log_event(severity, code, message, context)
        web_request.send({"success": True, "event": event})
        return event

    def _handle_clear_errors_request(self, web_request):
        """API endpoint: Clear error history"""
        self.error_history.clear()
        logging.info("Error history cleared")
        web_request.send({"success": True})

    # G-code Commands

    cmd_SYSTEM_STATUS_help = "Display complete system status"
    def cmd_SYSTEM_STATUS(self, gcmd):
        eventtime = self.reactor.monotonic()
        status = self.aggregate_status(eventtime)

        # Format output for console
        gcmd.respond_info("=== System Status ===")
        gcmd.respond_info("State: %s" % status["state"]["current"])
        gcmd.respond_info("Position: X=%.2f Y=%.2f Z=%.2f" % (
            status["motion"]["position"]["x"],
            status["motion"]["position"]["y"],
            status["motion"]["position"]["z"]))

        if "extruder" in status["thermal"]:
            gcmd.respond_info("Hotend: %.1f/%.1f°C" % (
                status["thermal"]["extruder"]["current"],
                status["thermal"]["extruder"]["target"]))

        gcmd.respond_info("CFS Connected: %s" % status["cfs"]["connected"])
        gcmd.respond_info("Recent errors: %d" % len(self.error_history))

    cmd_LOG_ERROR_help = "Log a custom error (LOG_ERROR CODE=E999 MSG='message')"
    def cmd_LOG_ERROR(self, gcmd):
        code = gcmd.get('CODE', 'U000')
        message = gcmd.get('MSG', 'User error')
        severity = gcmd.get('SEVERITY', 'ERROR')

        self.log_event(severity, code, message)
        gcmd.respond_info("Error logged: [%s] %s" % (code, message))

    cmd_SHOW_ERRORS_help = "Show recent errors"
    def cmd_SHOW_ERRORS(self, gcmd):
        limit = gcmd.get_int('LIMIT', 10, minval=1, maxval=100)

        gcmd.respond_info("=== Recent Errors (last %d) ===" % limit)

        errors = list(self.error_history)[-limit:]
        for err in errors:
            timestamp = time.strftime("%H:%M:%S", time.localtime(err["timestamp"]))
            gcmd.respond_info("[%s] %s %s: %s" % (
                timestamp, err["severity"], err["code"], err["message"]))

        if not errors:
            gcmd.respond_info("No errors logged")

    cmd_DEBUG_HOMING_help = "Show homing/probing state and timing diagnostics"
    def cmd_DEBUG_HOMING(self, gcmd):
        eventtime = self.reactor.monotonic()

        gcmd.respond_info("=== Homing Debug Info ===")
        gcmd.respond_info("is_homing: %s" % self.is_homing)
        gcmd.respond_info("is_probing: %s" % self.is_probing)
        gcmd.respond_info("in_critical_operation: %s" % self._in_critical_operation())
        gcmd.respond_info("safe_query_mode: %s" % self.safe_query_mode)
        gcmd.respond_info("would_use_cache: %s" % self._should_use_cache(eventtime))
        gcmd.respond_info("cache_age: %.3f seconds" % (eventtime - self.cache_timestamp if self.cache_timestamp > 0 else 0))
        gcmd.respond_info("is_printing: %s" % self._is_printing())

        # Try to get endstop status safely
        try:
            query_endstops = self.printer.lookup_object('query_endstops', None)
            if query_endstops:
                endstops_status = query_endstops.get_status(eventtime)
                gcmd.respond_info("last_query: %s" % endstops_status.get('last_query', {}))
        except Exception as e:
            gcmd.respond_info("Could not query endstops: %s" % str(e))

    def get_status(self, eventtime):
        """Called by Klipper to get status for webhooks"""
        return {
            "error_count": len(self.error_history),
            "last_error": self.error_history[-1] if self.error_history else None,
            "current_state": self._get_current_state()
        }

def load_config(config):
    return SystemMonitor(config)
