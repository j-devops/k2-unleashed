#include <string.h>
#include "basecmd.h" // oid_alloc
#include "board/irq.h"
#include "command.h"
#include "gpio.h"
#include "internal.h"
#include "sched.h"
#include "gd32f30x_rcu.h"

#if CONFIG_MACH_GD32F303XB
DECL_ENUMERATION_RANGE("pin","PA0",GPIO('A',0),16);
DECL_ENUMERATION_RANGE("pin","PB0",GPIO('B',0),16);
DECL_ENUMERATION_RANGE("pin","PC0",GPIO('C',0),16);
//DECL_ENUMERATION_RANGE("pin","PD0",GPIO('D',0),16);
//DECL_ENUMERATION_RANGE("pin","PE0",GPIO('E',0),16);
//DECL_ENUMERATION_RANGE("pin","PF0",GPIO('F',0),16);
//DECL_ENUMERATION_RANGE("pin","PG0",GPIO('G',0),16);
#elif CONFIG_MACH_GD32F303XE
DECL_ENUMERATION_RANGE("pin","PA0",GPIO('A',0),16);
DECL_ENUMERATION_RANGE("pin","PB0",GPIO('B',0),16);
DECL_ENUMERATION_RANGE("pin","PC0",GPIO('C',0),16);
DECL_ENUMERATION_RANGE("pin","PD0",GPIO('D',0),16);
//DECL_ENUMERATION_RANGE("pin","PE0",GPIO('E',0),16);
//DECL_ENUMERATION_RANGE("pin","PF0",GPIO('F',0),16);
//DECL_ENUMERATION_RANGE("pin","PG0",GPIO('G',0),16);
#endif

uint32_t gpio_port_base[] = {GPIOA,GPIOB,GPIOC,GPIOD,GPIOE,GPIOF,GPIOG};

uint32_t gpio_pclk[] = {RCU_GPIOA,RCU_GPIOB,RCU_GPIOC,RCU_GPIOD,RCU_GPIOE,RCU_GPIOF,RCU_GPIOG};

uint32_t
get_pclock_frequency(uint32_t periph_base)
{
	if(periph_base == 0)
	{
		return AHB_FREQ >> 1; 
	}
	else
	{
		return APB2_ADC_FREQ;
	}
}

uint32_t is_enable_pclock(uint32_t pclk)
{
	return RCU_REG_VAL(pclk) & BIT(RCU_BIT_POS(pclk));
}

void enable_pclock(uint32_t pclk)
{
	RCU_REG_VAL(pclk) |= BIT(RCU_BIT_POS(pclk));

	return;
}

/*
 * @gpio 
 * @otype 0=output;1=input;2=analog;3=AFIO
*/
void gpio_peripheral(uint32_t gpio, uint32_t otype, uint32_t pull_up)
{
	uint16_t i;

    uint32_t temp_mode = 0U;

    uint32_t reg = 0U;

	uint32_t speed = GPIO_OSPEED_50MHZ;

	uint32_t pinmode = 0;

	uint32_t port =  GPIO2PORT(gpio);
	
	uint16_t pin = GPIO2BIT(gpio);
		
	uint32_t gpio_periph = gpio_port_base[port];
	
	enable_pclock(gpio_pclk[port]);

	if(otype == 0)
	{
		if(pull_up == 1)
		{
			pinmode = GPIO_MODE_OUT_PP;
		}
		else
		{
			pinmode = GPIO_MODE_OUT_OD;
		}
	}
	else if(otype == 1)
	{
		if(pull_up == 0)
		{
			pinmode = GPIO_MODE_IPD;
		}
		else if(pull_up == 1)
		{
			pinmode = GPIO_MODE_IPU;	
		}
		else
		{
			pinmode = GPIO_MODE_IN_FLOATING;
		}
	}
	else if(otype == 2)
	{
		pinmode = GPIO_MODE_AIN;	
	}
	else if(otype == 3)
	{
		if(pull_up == 0)
		{
			pinmode = GPIO_MODE_AF_OD;	
		}
		else
		{
			pinmode = GPIO_MODE_AF_PP;	
		}
	}
	else
	{
		shutdown("gpio initialize fail");
	}

    /* GPIO mode configuration */
    temp_mode = (uint32_t)(pinmode & ((uint32_t)0x0FU));
    
    /* GPIO speed configuration */
    if(((uint32_t)0x00U) != ((uint32_t)pinmode & ((uint32_t)0x10U)))
	{
        /* output mode max speed */
        if(GPIO_OSPEED_MAX == (uint32_t)speed)
		{
            temp_mode |= (uint32_t)0x03U;
            /* set the corresponding SPD bit */
            GPIOx_SPD(gpio_periph) |= (uint32_t)pin ;
        }
		else
		{
            /* output mode max speed:10MHz,2MHz,50MHz */
            temp_mode |= (uint32_t)speed;
        }
    }

    /* configure the eight low port pins with GPIO_CTL0 */
    for(i = 0U;i < 8U;i++)
	{
        if((1U << i) & pin)
		{
            reg = GPIO_CTL0(gpio_periph);
            
            /* clear the specified pin mode bits */
            reg &= ~GPIO_MODE_MASK(i);
            
			/* set the specified pin mode bits */
            reg |= GPIO_MODE_SET(i, temp_mode);
            
            /* set IPD or IPU */
            if(GPIO_MODE_IPD == pinmode)
			{
                /* reset the corresponding OCTL bit */
                GPIO_BC(gpio_periph) = (uint32_t)((1U << i) & pin);
            }
			else
			{
                /* set the corresponding OCTL bit */
                if(GPIO_MODE_IPU == pinmode)
				{
                    GPIO_BOP(gpio_periph) = (uint32_t)((1U << i) & pin);
                }
            }
            /* set GPIO_CTL0 register */
            GPIO_CTL0(gpio_periph) = reg;
        }
    }

    /* configure the eight high port pins with GPIO_CTL1 */
    for(i = 8U;i < 16U;i++)
	{
        if((1U << i) & pin)
		{
            reg = GPIO_CTL1(gpio_periph);
            
            /* clear the specified pin mode bits */
            reg &= ~GPIO_MODE_MASK(i - 8U);
            
			/* set the specified pin mode bits */
            reg |= GPIO_MODE_SET(i - 8U, temp_mode);
            
            /* set IPD or IPU */
            if(GPIO_MODE_IPD == pinmode)
			{
                /* reset the corresponding OCTL bit */
                GPIO_BC(gpio_periph) = (uint32_t)((1U << i) & pin);
            }
			else
			{
                /* set the corresponding OCTL bit */
                if(GPIO_MODE_IPU == pinmode)
				{
                    GPIO_BOP(gpio_periph) = (uint32_t)((1U << i) & pin);
                }
            }

            /* set GPIO_CTL1 register */
            GPIO_CTL1(gpio_periph) = reg;
        }
	}
}

void
gpio_out_reset(struct gpio_out g, uint8_t val)
{
	uint32_t port = GPIO2PORT(g.pin);

	uint32_t pin = GPIO2BIT(g.pin);
		
	irqstatus_t flag = irq_save();

	gpio_peripheral(g.pin, 0, 1);

	if(!val)
	{
		GPIO_BC(gpio_port_base[port]) = (uint32_t)pin;
	}
	else
	{
		GPIO_BOP(gpio_port_base[port]) = (uint32_t)pin;
	}

	irq_restore(flag);

	return;
}

struct gpio_out
gpio_out_setup(uint8_t pin, uint8_t val)
{
	if(GPIO2PORT(pin) >= sizeof(gpio_port_base) / sizeof(gpio_port_base[0]))
	{
		goto fail;
	}

	struct gpio_out g = {.pin = pin};

	gpio_out_reset(g,val);

	return g;
fail:
	shutdown("not an output pin");
}

void
gpio_out_toggle_noirq(struct gpio_out g)
{
	uint32_t port = GPIO2PORT(g.pin);

	uint32_t pin = GPIO2BIT(g.pin);
	
	if(GPIO_OCTL(gpio_port_base[port]) & (pin))
	{
		GPIO_BC(gpio_port_base[port]) = (uint32_t)pin;
	}
	else
	{
		GPIO_BOP(gpio_port_base[port]) = (uint32_t)pin;
	}	
	
	return;	
}

void 
gpio_out_toggle(struct gpio_out g)
{
	irqstatus_t flag = irq_save();
	
	gpio_out_toggle_noirq(g);

	irq_restore(flag);

	return;
}

uint8_t 
gpio_out_read(uint8_t gpioIndx)
{
	uint32_t port = GPIO2PORT(gpioIndx);

	uint32_t pin = GPIO2BIT(gpioIndx);
	
	return !!(GPIO_OCTL(gpio_port_base[port]) & (pin));
}

void
command_query_gpio_status(uint32_t *args)
{
    sendf("gpio_status oid=%c status=%c", args[0], gpio_out_read(args[1]));

    return;
}
DECL_COMMAND(command_query_gpio_status, "query_gpio_status oid=%c gpio_pin=%c");

void 
gpio_out_write(struct gpio_out g, uint8_t val)
{
	uint32_t port = GPIO2PORT(g.pin);

	uint32_t pin = GPIO2BIT(g.pin);
	
	if(!val)
	{
		GPIO_BC(gpio_port_base[port]) = (uint32_t)pin;
	}
	else
	{
		GPIO_BOP(gpio_port_base[port]) = (uint32_t)pin;
	}

	return;
}

struct gpio_in
gpio_in_setup(uint8_t pin, uint8_t pull_up)
{

	if(GPIO2PORT(pin) >= sizeof(gpio_port_base) / sizeof(gpio_port_base[0]))
	{
		goto fail;
	}

	struct gpio_in g = {.pin = pin};

	gpio_in_reset(g,pull_up);

	return g;
fail:
	shutdown("Not an input pin");
}

void
gpio_in_reset(struct gpio_in g, int8_t pull_up)
{
	irqstatus_t flag = irq_save();

	gpio_peripheral(g.pin, 1, pull_up);
	
	irq_restore(flag);
}

uint8_t
gpio_in_read(struct gpio_in g)
{
	uint32_t port = GPIO2PORT(g.pin);

	uint32_t pin = GPIO2BIT(g.pin);

	return (!!(GPIO_ISTAT(gpio_port_base[port]) & pin));
}

#define AFIO_EXTI_SOURCE_FIELDS            ((uint8_t)0x04U)         /*!< select AFIO exti source registers */
#define LSB_16BIT_MASK                     ((uint16_t)0xFFFFU)      /*!< LSB 16-bit mask */
#define PCF_POSITION_MASK                  ((uint32_t)0x000F0000U)  /*!< AFIO_PCF register position mask */
#define PCF_SWJCFG_MASK                    ((uint32_t)0xF0FFFFFFU)  /*!< AFIO_PCF register SWJCFG mask */
#define PCF_LOCATION1_MASK                 ((uint32_t)0x00200000U)  /*!< AFIO_PCF register location1 mask */
#define PCF_LOCATION2_MASK                 ((uint32_t)0x00100000U)  /*!< AFIO_PCF register location2 mask */
#define AFIO_PCF1_FIELDS                   ((uint32_t)0x80000000U)  /*!< select AFIO_PCF1 register */

void gpio_pin_remap_config(uint32_t gpio_remap, ControlStatus newvalue)
{
	    uint32_t remap1 = 0U, remap2 = 0U, temp_reg = 0U, temp_mask = 0U;

    if(((uint32_t)0x80000000U) == (gpio_remap & 0x80000000U)){
        /* get AFIO_PCF1 regiter value */
        temp_reg = AFIO_PCF1;
    }else{
        /* get AFIO_PCF0 regiter value */
        temp_reg = AFIO_PCF0;
    }

    temp_mask = (gpio_remap & PCF_POSITION_MASK) >> 0x10U;
    remap1 = gpio_remap & LSB_16BIT_MASK;

    /* judge pin remap type */
    if((PCF_LOCATION1_MASK | PCF_LOCATION2_MASK) == (gpio_remap & (PCF_LOCATION1_MASK | PCF_LOCATION2_MASK))){
        temp_reg &= PCF_SWJCFG_MASK;
        AFIO_PCF0 &= PCF_SWJCFG_MASK;
    }else if(PCF_LOCATION2_MASK == (gpio_remap & PCF_LOCATION2_MASK)){
        remap2 = ((uint32_t)0x03U) << temp_mask;
        temp_reg &= ~remap2;
        temp_reg |= ~PCF_SWJCFG_MASK;
    }else{
        temp_reg &= ~(remap1 << ((gpio_remap >> 0x15U)*0x10U));
        temp_reg |= ~PCF_SWJCFG_MASK;
    }
    
    /* set pin remap value */
    if(DISABLE != newvalue){
        temp_reg |= (remap1 << ((gpio_remap >> 0x15U)*0x10U));
    }
    
    if(AFIO_PCF1_FIELDS == (gpio_remap & AFIO_PCF1_FIELDS)){
        /* set AFIO_PCF1 regiter value */
        AFIO_PCF1 = temp_reg;
    }else{
        /* set AFIO_PCF0 regiter value */
        AFIO_PCF0 = temp_reg;
    }
}

void rcu_periph_clock_enable(rcu_periph_enum periph)
{
    RCU_REG_VAL(periph) |= BIT(RCU_BIT_POS(periph));
}
