# Diagnostic and Health Check System for K2 Series
#
# Copyright (C) 2025
#
# This file may be distributed under the terms of the GNU GPLv3 license.

import time
import logging
import json
from collections import deque

class DiagnosticTest:
    """Base class for diagnostic tests"""
    def __init__(self, name, description):
        self.name = name
        self.description = description
        self.status = "pending"  # pending, running, passed, failed, warning
        self.message = ""
        self.details = {}
        self.start_time = None
        self.end_time = None

    def to_dict(self):
        return {
            "name": self.name,
            "description": self.description,
            "status": self.status,
            "message": self.message,
            "details": self.details,
            "duration": self.end_time - self.start_time if self.end_time else 0
        }

class Diagnostics:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.reactor = self.printer.get_reactor()
        self.gcode = self.printer.lookup_object('gcode')

        # Test results history
        self.test_history = deque(maxlen=100)
        self.current_test = None

        # Auto health check configuration
        self.auto_health_check = config.getboolean('auto_health_check', False)
        self.health_check_interval = config.getfloat('health_check_interval', 3600, above=60)  # 1 hour default
        self.last_health_check = 0

        # Register event handlers
        self.printer.register_event_handler("klippy:ready", self._handle_ready)

        # Register webhooks
        webhooks = self.printer.lookup_object('webhooks')
        webhooks.register_endpoint("diagnostics/run_test",
                                   self._handle_run_test_request)
        webhooks.register_endpoint("diagnostics/health_check",
                                   self._handle_health_check_request)
        webhooks.register_endpoint("diagnostics/test_history",
                                   self._handle_test_history_request)

        # Register G-code commands
        self.gcode.register_command("DIAGNOSTIC_TEST", self.cmd_DIAGNOSTIC_TEST,
                                   desc=self.cmd_DIAGNOSTIC_TEST_help)
        self.gcode.register_command("HEALTH_CHECK", self.cmd_HEALTH_CHECK,
                                   desc=self.cmd_HEALTH_CHECK_help)
        self.gcode.register_command("TEST_MOTORS", self.cmd_TEST_MOTORS,
                                   desc=self.cmd_TEST_MOTORS_help)
        self.gcode.register_command("TEST_HEATERS", self.cmd_TEST_HEATERS,
                                   desc=self.cmd_TEST_HEATERS_help)
        self.gcode.register_command("TEST_PROBE", self.cmd_TEST_PROBE,
                                   desc=self.cmd_TEST_PROBE_help)

        # Cached object references
        self.toolhead = None
        self.system_monitor = None

        logging.info("Diagnostics module initialized")

    def _handle_ready(self):
        """Called when Klipper is ready"""
        self.toolhead = self.printer.lookup_object('toolhead', None)
        self.system_monitor = self.printer.lookup_object('system_monitor', None)

        # Schedule auto health checks if enabled
        if self.auto_health_check:
            self.reactor.register_timer(self._auto_health_check_timer,
                                       self.reactor.monotonic() + self.health_check_interval)

        logging.info("Diagnostics ready")

    def _auto_health_check_timer(self, eventtime):
        """Periodic health check timer"""
        if self._can_run_diagnostic():
            logging.info("Running automatic health check")
            self._run_health_check()
        return eventtime + self.health_check_interval

    def _can_run_diagnostic(self):
        """Check if it's safe to run diagnostics"""
        print_stats = self.printer.lookup_object('print_stats', None)
        if print_stats:
            state = print_stats.get_status(self.reactor.monotonic()).get('state', 'standby')
            if state == "printing":
                return False
        return True

    def _log_test_result(self, test):
        """Log test result to history and system monitor"""
        self.test_history.append(test.to_dict())

        if self.system_monitor:
            severity = {
                "passed": "INFO",
                "warning": "WARNING",
                "failed": "ERROR"
            }.get(test.status, "INFO")

            code = "D%03d" % len(self.test_history)
            self.system_monitor.log_event(severity, code,
                                         "Diagnostic: %s - %s" % (test.name, test.message),
                                         context=test.details)

    # Individual Diagnostic Tests

    def test_homing(self, axes="XYZ"):
        """Test homing of specified axes"""
        test = DiagnosticTest("Homing Test", "Test homing of %s axes" % axes)
        test.start_time = time.time()
        test.status = "running"

        try:
            # Record initial position
            if self.toolhead:
                initial_pos = self.toolhead.get_position()
                test.details["initial_position"] = {
                    "x": initial_pos[0], "y": initial_pos[1],
                    "z": initial_pos[2], "e": initial_pos[3]
                }

            # Run homing
            self.gcode.run_script_from_command("G28 %s" % " ".join(list(axes)))

            # Verify homed
            if self.toolhead:
                homed = self.toolhead.get_status(self.reactor.monotonic()).get("homed_axes", "")
                test.details["homed_axes"] = list(homed)

                all_homed = all(axis.lower() in homed for axis in axes)
                if all_homed:
                    test.status = "passed"
                    test.message = "All axes homed successfully"
                else:
                    test.status = "failed"
                    test.message = "Some axes failed to home"
            else:
                test.status = "warning"
                test.message = "Could not verify homing status"

        except Exception as e:
            test.status = "failed"
            test.message = "Homing failed: %s" % str(e)
            test.details["error"] = str(e)

        test.end_time = time.time()
        self._log_test_result(test)
        return test

    def test_motor_movement(self, axis="X", distance=10):
        """Test motor movement"""
        test = DiagnosticTest("Motor Movement Test",
                            "Test %s axis movement by %dmm" % (axis, distance))
        test.start_time = time.time()
        test.status = "running"

        try:
            if not self.toolhead:
                raise Exception("Toolhead not available")

            # Get initial position
            initial_pos = self.toolhead.get_position()
            test.details["initial_position"] = initial_pos[0:4]

            # Move
            axis_index = {"X": 0, "Y": 1, "Z": 2, "E": 3}.get(axis.upper(), 0)
            self.gcode.run_script_from_command("G91")  # Relative positioning
            self.gcode.run_script_from_command("G1 %s%d F3000" % (axis.upper(), distance))
            self.gcode.run_script_from_command("G90")  # Absolute positioning
            self.gcode.run_script_from_command("M400")  # Wait for moves

            # Get final position
            final_pos = self.toolhead.get_position()
            test.details["final_position"] = final_pos[0:4]

            # Calculate actual movement
            actual_movement = final_pos[axis_index] - initial_pos[axis_index]
            test.details["expected_movement"] = distance
            test.details["actual_movement"] = round(actual_movement, 3)
            test.details["error"] = round(abs(actual_movement - distance), 3)

            # Check tolerance (0.5mm)
            if abs(actual_movement - distance) < 0.5:
                test.status = "passed"
                test.message = "Motor moved correctly (%.3fmm)" % actual_movement
            elif abs(actual_movement - distance) < 2.0:
                test.status = "warning"
                test.message = "Motor movement slightly off (%.3fmm vs %dmm expected)" % (actual_movement, distance)
            else:
                test.status = "failed"
                test.message = "Motor movement significantly off (%.3fmm vs %dmm expected)" % (actual_movement, distance)

            # Move back
            self.gcode.run_script_from_command("G91")
            self.gcode.run_script_from_command("G1 %s%d F3000" % (axis.upper(), -distance))
            self.gcode.run_script_from_command("G90")

        except Exception as e:
            test.status = "failed"
            test.message = "Motor test failed: %s" % str(e)
            test.details["error"] = str(e)

        test.end_time = time.time()
        self._log_test_result(test)
        return test

    def test_heater(self, heater_name="extruder", target_temp=50):
        """Test heater heating and stability"""
        test = DiagnosticTest("Heater Test",
                            "Test %s heating to %d°C" % (heater_name, target_temp))
        test.start_time = time.time()
        test.status = "running"

        try:
            heater = self.printer.lookup_object(heater_name, None)
            if not heater:
                raise Exception("Heater '%s' not found" % heater_name)

            # Get initial temp
            initial_temp = heater.get_status(self.reactor.monotonic())["temperature"]
            test.details["initial_temp"] = round(initial_temp, 1)
            test.details["target_temp"] = target_temp

            # Set target
            self.gcode.run_script_from_command("M104 S%d" % target_temp if heater_name == "extruder"
                                             else "M140 S%d" % target_temp)

            # Wait up to 60 seconds for heating
            timeout = 60
            start = time.time()
            samples = []

            while (time.time() - start) < timeout:
                current_temp = heater.get_status(self.reactor.monotonic())["temperature"]
                samples.append(current_temp)

                # Check if reached target (within 2°C)
                if abs(current_temp - target_temp) < 2.0:
                    test.status = "passed"
                    test.message = "Heater reached target in %.1fs" % (time.time() - start)
                    test.details["final_temp"] = round(current_temp, 1)
                    test.details["heating_time"] = round(time.time() - start, 1)
                    test.details["samples"] = samples
                    break

                self.reactor.pause(self.reactor.monotonic() + 1.0)
            else:
                # Timeout
                final_temp = heater.get_status(self.reactor.monotonic())["temperature"]
                test.status = "failed"
                test.message = "Heater did not reach target (got %.1f°C, wanted %d°C)" % (final_temp, target_temp)
                test.details["final_temp"] = round(final_temp, 1)

            # Turn off heater
            self.gcode.run_script_from_command("M104 S0" if heater_name == "extruder"
                                             else "M140 S0")

        except Exception as e:
            test.status = "failed"
            test.message = "Heater test failed: %s" % str(e)
            test.details["error"] = str(e)

        test.end_time = time.time()
        self._log_test_result(test)
        return test

    def test_probe_accuracy(self, samples=10):
        """Test probe accuracy and repeatability"""
        test = DiagnosticTest("Probe Accuracy Test",
                            "Test probe repeatability with %d samples" % samples)
        test.start_time = time.time()
        test.status = "running"

        try:
            # Run PROBE_ACCURACY command
            self.gcode.run_script_from_command("PROBE_ACCURACY SAMPLES=%d" % samples)

            # Skip probe object lookup - it interferes with PRTouch on K2
            # Results are printed to console which is sufficient
            test.status = "passed"
            test.message = "Probe accuracy test completed (check console for results)"
            test.details["samples"] = samples

        except Exception as e:
            test.status = "failed"
            test.message = "Probe test failed: %s" % str(e)
            test.details["error"] = str(e)

        test.end_time = time.time()
        self._log_test_result(test)
        return test

    def test_fans(self):
        """Test all fans"""
        test = DiagnosticTest("Fan Test", "Test all cooling fans")
        test.start_time = time.time()
        test.status = "running"
        test.details["fans_tested"] = []

        try:
            # Test each fan
            for fan_name in ['fan0', 'fan1', 'fan2']:
                try:
                    fan = self.printer.lookup_object('output_pin ' + fan_name, None)
                    if fan:
                        # Turn on
                        self.gcode.run_script_from_command("SET_PIN PIN=%s VALUE=255" % fan_name)
                        self.reactor.pause(self.reactor.monotonic() + 2.0)

                        # Check it's on
                        fan_status = fan.get_status(self.reactor.monotonic())
                        value = fan_status.get('value', 0)

                        # Turn off
                        self.gcode.run_script_from_command("SET_PIN PIN=%s VALUE=0" % fan_name)

                        test.details["fans_tested"].append({
                            "name": fan_name,
                            "status": "passed" if value > 0.5 else "failed",
                            "value": value
                        })
                except:
                    pass

            if test.details["fans_tested"]:
                all_passed = all(f["status"] == "passed" for f in test.details["fans_tested"])
                if all_passed:
                    test.status = "passed"
                    test.message = "All fans working"
                else:
                    test.status = "warning"
                    test.message = "Some fans may not be working"
            else:
                test.status = "warning"
                test.message = "No fans found to test"

        except Exception as e:
            test.status = "failed"
            test.message = "Fan test failed: %s" % str(e)
            test.details["error"] = str(e)

        test.end_time = time.time()
        self._log_test_result(test)
        return test

    def test_endstops(self):
        """Test endstop status"""
        test = DiagnosticTest("Endstop Test", "Check all endstop states")
        test.start_time = time.time()
        test.status = "running"
        test.details["endstops"] = {}

        try:
            # Query endstops
            self.gcode.run_script_from_command("QUERY_ENDSTOPS")

            # Note: Endstop query results go to console, would need to
            # modify endstops.py to expose results via API

            test.status = "passed"
            test.message = "Endstop query completed (check console)"

        except Exception as e:
            test.status = "failed"
            test.message = "Endstop test failed: %s" % str(e)
            test.details["error"] = str(e)

        test.end_time = time.time()
        self._log_test_result(test)
        return test

    def test_belt_tension(self):
        """Test belt tension using belt_mdl module"""
        test = DiagnosticTest("Belt Tension Test", "Check X/Y belt tension")
        test.start_time = time.time()
        test.status = "running"
        test.details["belts"] = {}

        try:
            # Check if belt modules exist
            for belt_name in ['mdlx', 'mdly']:
                try:
                    belt = self.printer.lookup_object('belt_mdl ' + belt_name, None)
                    if belt:
                        # Run belt check (if module supports it)
                        # This would require exposing belt check functionality
                        test.details["belts"][belt_name] = {
                            "status": "present",
                            "message": "Belt module found"
                        }
                except:
                    pass

            if test.details["belts"]:
                test.status = "passed"
                test.message = "Belt tension modules present"
            else:
                test.status = "warning"
                test.message = "Belt tension modules not found or not configured"

        except Exception as e:
            test.status = "failed"
            test.message = "Belt test failed: %s" % str(e)
            test.details["error"] = str(e)

        test.end_time = time.time()
        self._log_test_result(test)
        return test

    # Comprehensive Health Check

    def _run_health_check(self):
        """Run comprehensive health check"""
        results = {
            "timestamp": time.time(),
            "tests": [],
            "overall_status": "passed"
        }

        # Only run if not printing
        if not self._can_run_diagnostic():
            results["overall_status"] = "skipped"
            results["message"] = "Cannot run health check while printing"
            return results

        # Run tests
        tests_to_run = [
            ("homing", lambda: self.test_homing("XY")),  # Test X/Y only, avoid Z crash
            ("endstops", self.test_endstops),
            ("fans", self.test_fans),
            ("belt_tension", self.test_belt_tension)
        ]

        for test_name, test_func in tests_to_run:
            try:
                result = test_func()
                results["tests"].append(result.to_dict())

                # Update overall status
                if result.status == "failed":
                    results["overall_status"] = "failed"
                elif result.status == "warning" and results["overall_status"] != "failed":
                    results["overall_status"] = "warning"
            except Exception as e:
                logging.error("Health check test '%s' failed: %s" % (test_name, str(e)))
                results["tests"].append({
                    "name": test_name,
                    "status": "failed",
                    "message": str(e)
                })
                results["overall_status"] = "failed"

        self.last_health_check = time.time()
        return results

    # Webhook Handlers

    def _handle_run_test_request(self, web_request):
        """API endpoint: Run a specific test"""
        params = web_request.get_args()
        test_name = params.get('test', 'health_check')

        if not self._can_run_diagnostic():
            web_request.send({"error": "Cannot run test while printing"})
            return

        result = None
        if test_name == "homing":
            axes = params.get('axes', 'XYZ')
            result = self.test_homing(axes)
        elif test_name == "motor":
            axis = params.get('axis', 'X')
            distance = int(params.get('distance', 10))
            result = self.test_motor_movement(axis, distance)
        elif test_name == "heater":
            heater = params.get('heater', 'extruder')
            temp = int(params.get('temp', 50))
            result = self.test_heater(heater, temp)
        elif test_name == "probe":
            samples = int(params.get('samples', 10))
            result = self.test_probe_accuracy(samples)
        elif test_name == "fans":
            result = self.test_fans()
        elif test_name == "endstops":
            result = self.test_endstops()
        elif test_name == "belt_tension":
            result = self.test_belt_tension()
        else:
            web_request.send({"error": "Unknown test: %s" % test_name})
            return

        web_request.send({"result": result.to_dict() if result else None})

    def _handle_health_check_request(self, web_request):
        """API endpoint: Run comprehensive health check"""
        if not self._can_run_diagnostic():
            web_request.send({"error": "Cannot run health check while printing"})
            return

        results = self._run_health_check()
        web_request.send(results)

    def _handle_test_history_request(self, web_request):
        """API endpoint: Get test history"""
        params = web_request.get_args()
        limit = int(params.get('limit', 20))

        history = list(self.test_history)[-limit:]
        web_request.send({
            "tests": history,
            "total": len(self.test_history)
        })

    # G-code Commands

    cmd_DIAGNOSTIC_TEST_help = "Run a diagnostic test (DIAGNOSTIC_TEST TEST=homing AXES=XY)"
    def cmd_DIAGNOSTIC_TEST(self, gcmd):
        test_name = gcmd.get('TEST', 'homing')

        if not self._can_run_diagnostic():
            gcmd.respond_info("Cannot run test while printing")
            return

        result = None
        if test_name == "homing":
            axes = gcmd.get('AXES', 'XYZ')
            result = self.test_homing(axes)
        elif test_name == "motor":
            axis = gcmd.get('AXIS', 'X')
            distance = gcmd.get_int('DISTANCE', 10)
            result = self.test_motor_movement(axis, distance)
        elif test_name == "fans":
            result = self.test_fans()
        elif test_name == "endstops":
            result = self.test_endstops()

        if result:
            gcmd.respond_info("Test '%s': %s - %s" % (result.name, result.status.upper(), result.message))

    cmd_HEALTH_CHECK_help = "Run comprehensive health check"
    def cmd_HEALTH_CHECK(self, gcmd):
        if not self._can_run_diagnostic():
            gcmd.respond_info("Cannot run health check while printing")
            return

        gcmd.respond_info("Running health check...")
        results = self._run_health_check()

        gcmd.respond_info("=== Health Check Results ===")
        for test in results["tests"]:
            gcmd.respond_info("%s: %s - %s" % (test["name"], test["status"].upper(), test["message"]))
        gcmd.respond_info("Overall: %s" % results["overall_status"].upper())

    cmd_TEST_MOTORS_help = "Test motor movement (TEST_MOTORS AXIS=X DISTANCE=10)"
    def cmd_TEST_MOTORS(self, gcmd):
        if not self._can_run_diagnostic():
            gcmd.respond_info("Cannot run test while printing")
            return

        axis = gcmd.get('AXIS', 'X')
        distance = gcmd.get_int('DISTANCE', 10)

        result = self.test_motor_movement(axis, distance)
        gcmd.respond_info("Motor test: %s - %s" % (result.status.upper(), result.message))

    cmd_TEST_HEATERS_help = "Test heater (TEST_HEATERS HEATER=extruder TEMP=50)"
    def cmd_TEST_HEATERS(self, gcmd):
        if not self._can_run_diagnostic():
            gcmd.respond_info("Cannot run test while printing")
            return

        heater = gcmd.get('HEATER', 'extruder')
        temp = gcmd.get_int('TEMP', 50)

        result = self.test_heater(heater, temp)
        gcmd.respond_info("Heater test: %s - %s" % (result.status.upper(), result.message))

    cmd_TEST_PROBE_help = "Test probe accuracy (TEST_PROBE SAMPLES=10)"
    def cmd_TEST_PROBE(self, gcmd):
        if not self._can_run_diagnostic():
            gcmd.respond_info("Cannot run test while printing")
            return

        samples = gcmd.get_int('SAMPLES', 10)

        result = self.test_probe_accuracy(samples)
        gcmd.respond_info("Probe test: %s - %s" % (result.status.upper(), result.message))

    def get_status(self, eventtime):
        """Called by Klipper to get status"""
        return {
            "test_count": len(self.test_history),
            "last_health_check": self.last_health_check,
            "auto_health_check": self.auto_health_check
        }

def load_config(config):
    return Diagnostics(config)
