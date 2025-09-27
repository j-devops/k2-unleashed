// Report on user interface buttons
//
// Copyright (C) 2023  WangYuLong <wangyulong@sina.com>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

#include "basecmd.h"    // oid_alloc
#include "command.h"    // DECL_COMMAND
#include "sched.h"      // struct timer
#include "board/gpio.h" // struct gpio_in
#include "board/misc.h" // timer_from_us
#include "autoconf.h"   // CONFIG_CLOCK_FREQ
#include "i2ccmds.h"    // i2cdev_oid_lookup
#include "stepper.h"

#include <string.h>
#include <math.h>

#define PRTOUCH_V3_VERSION  71

DECL_COMMAND(command_config_prtouch_pres, "config_prtouch_pres oid=%c idx=%c swp_pin=%u clk_pin=%u sdo_pin=%u");
DECL_COMMAND(command_start_prtouch_pres, "start_prtouch_pres oid=%c cfg_regs=%c acq_tick=%u ned_tftr=%c ned_hftr=%c ned_lftr=%u min_hold=%i max_hold=%i add_hold=%i lmt_dead=%u");
DECL_COMMAND(command_stop_prtouch_pres, "stop_prtouch_pres oid=%c sta_swap=%c");
DECL_COMMAND(command_read_prtouch_pres, "read_prtouch_pres oid=%c is_src=%c ch=%c idx=%c len=%c");
DECL_COMMAND(command_config_prtouch_step, "config_prtouch_step oid=%c oid_xstp=%u oid_ystp=%u oid_zstp=%u swp_pin=%u");
DECL_COMMAND(command_start_prtouch_step, "start_prtouch_step oid=%c aqc_tick=%u");
DECL_COMMAND(command_stop_prtouch_step, "stop_prtouch_step oid=%c");
DECL_COMMAND(command_read_prtouch_step, "read_prtouch_step oid=%c idx=%c len=%c");
DECL_COMMAND(command_cont_prtouch_step, "cont_prtouch_step oid=%c");
DECL_COMMAND(command_config_prtouch_apax, "config_prtouch_apax oid=%c oid_estp=%c");
DECL_COMMAND(command_start_prtouch_apax, "start_prtouch_apax oid=%c cfg_regs=%c acq_tick=%u");
DECL_COMMAND(command_stop_prtouch_apax, "stop_prtouch_apax oid=%c");

void
sendf_info(void)
{
    sendf("ack_prtouch oid=%c err=%c expar0=%u expar1=%u", 1, 0, 0, 0);

    sendf("resault_prtouch_step oid=%c buf_len=%c idx=%c len=%c ticks=%.*s datas=%.*s", 1, 0, 0, 0, "creality", "creality");
    
    sendf("resault_prtouch_step_cnt oid=%c cnt_x=%i cnt_y=%i cnt_z=%i", 1, 0, 0, 0);

    sendf("resault_prtouch_apax oid=%c ch=%c len=%c ticks=%.*s datas=%.*s espds=%.*s", 1, 0, 0, "creality", "creality", "creality");
}
