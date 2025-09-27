#include "autoconf.h" // CONFIG_CLOCK_FREQ
#include "basecmd.h" // oid_alloc
#include "board/gpio.h" // struct gpio
#include "board/irq.h" // irq_disable
#include "board/misc.h" // timer_read_time
#include "command.h" // shutdown
#include "sched.h" // sched_timer_dispatch

DECL_COMMAND(command_z_align_config,"config_z_align oid=%c");
DECL_COMMAND(command_z_align_add,"config_z_align_add oid=%c z_indx=%c zs_pin=%c zd_pin=%c zd_up=%c zes_pin=%c zes_untrig=%c");
DECL_COMMAND(command_z_align_force_stop,"z_align_force_stop oid=%c");
DECL_COMMAND(command_query_z_align, "query_z_align oid=%c enable=%c quickSpeed=%u slowSpeed=%u risingDist=%u filterCnt=%c safeDist=%u");
DECL_COMMAND(command_query_finetuning, "query_finetuning oid=%c enable=%c speed=%u maxDist=%u filterCnt=%c");
