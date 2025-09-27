#include <string.h> // memcpy
#include "board/gpio.h" // gpio_out_write
#include "board/irq.h" // irq_disable
#include "board/misc.h" // timer_read_time
#include "basecmd.h" // oid_alloc
#include "command.h" // DECL_COMMAND
#include "sched.h" // DECL_SHUTDOWN
#include "autoconf.h"
#include "internal.h"

#if CONFIG_TRANSPARENT_SERIAL

#if CONFIG_GD32_TRANSPARENT_SERIAL_USART2_PB10_PB11

#define USARTx              USART2

#define RCU_GPIOx           RCU_GPIOB

#define RCU_USARTx          RCU_USART2

#define GPIOx               GPIOB

#define GPIO_PIN_RX         GPIO_PIN_11

#define GPIO_PIN_TX         GPIO_PIN_10

#define USARTX_CLOCK_FREQ() (60000000)

#else

#error "check src/yourMCU/Kconfig"

#endif

#define TRANSPARENT_POLLING_PERIOD_TICKS        (CONFIG_CLOCK_FREQ / CONFIG_TRANSPARENT_SERIAL_BAUD * 5) //传输半个字节的时间长度

#define TRANSPARENT_DATA_LEN_MAX                (60)

#define TRANSPARENT_RX_TIMEOUT_NONE             (0xFFFFFFFF)

struct buffer_s 
{
    uint8_t *buf;

    uint8_t dataIndx;

    uint8_t expLen; 
    
    int8_t timeoutS; 

    uint32_t timeoutUs; 

    uint32_t startTime; 
};

struct transparent_s 
{
    struct timer timer;

    struct buffer_s txBuf;

    struct buffer_s rxBuf;

    uint8_t flag;
};

enum {START_RX = 0x01 << 1, START_REPORT = 0x01 << 2, START_TX = 0x01 << 3, RX_TIMEOUT = 0x01 << 4};

static uint8_t txBuf[TRANSPARENT_DATA_LEN_MAX] = {0};

static uint8_t rxBuf[TRANSPARENT_DATA_LEN_MAX] = {0};

static struct task_wake transparent_wake;

static void usart_init(void);

static void gpioInit(uint32_t gpio_periph, uint32_t mode, uint32_t speed, uint32_t pin);

static void gpioInit(uint32_t gpio_periph, uint32_t mode, uint32_t speed, uint32_t pin)
{
    uint16_t i;

    uint32_t temp_mode = 0U;

    uint32_t reg = 0U;

    temp_mode = (uint32_t)(mode & ((uint32_t)0x0FU));
    
    if(((uint32_t)0x00U) != ((uint32_t)mode & ((uint32_t)0x10U)))
    {
        if(GPIO_OSPEED_MAX == (uint32_t)speed)
        {
            temp_mode |= (uint32_t)0x03U;

            GPIOx_SPD(gpio_periph) |= (uint32_t)pin ;
        }
        else
        {
            temp_mode |= (uint32_t)speed;
        }
    }

    for(i = 0U;i < 8U;i++)
    {
        if((1U << i) & pin)
        {
            reg = GPIO_CTL0(gpio_periph);
            
            reg &= ~GPIO_MODE_MASK(i);

            reg |= GPIO_MODE_SET(i, temp_mode);
            
            if(GPIO_MODE_IPD == mode)
            {
                GPIO_BC(gpio_periph) = (uint32_t)((1U << i) & pin);
            }
            else
            {
                if(GPIO_MODE_IPU == mode)
                {
                    GPIO_BOP(gpio_periph) = (uint32_t)((1U << i) & pin);
                }
            }

            GPIO_CTL0(gpio_periph) = reg;
        }
    }
    for(i = 8U;i < 16U;i++)
    {
        if((1U << i) & pin)
        {
            reg = GPIO_CTL1(gpio_periph);
            
            reg &= ~GPIO_MODE_MASK(i - 8U);
                
            reg |= GPIO_MODE_SET(i - 8U, temp_mode);
            
            if(GPIO_MODE_IPD == mode)
            {
                GPIO_BC(gpio_periph) = (uint32_t)((1U << i) & pin);
            }
            else
            {
                if(GPIO_MODE_IPU == mode)
                {
                    GPIO_BOP(gpio_periph) = (uint32_t)((1U << i) & pin);
                }
            }
             
            GPIO_CTL1(gpio_periph) = reg;
        }
    }
}
static void usart_init(void)
{
    uint32_t uclk=0U, intdiv=0U, fradiv=0U, udiv=0U;

	RCU_REG_VAL(RCU_AF) |= BIT(RCU_BIT_POS(RCU_AF));
    
	RCU_REG_VAL(RCU_GPIOx) |= BIT(RCU_BIT_POS(RCU_GPIOx));

	RCU_REG_VAL(RCU_USARTx) |= BIT(RCU_BIT_POS(RCU_USARTx));

    gpioInit(GPIOx, GPIO_MODE_IN_FLOATING, GPIO_OSPEED_50MHZ, GPIO_PIN_RX);
	
    gpioInit(GPIOx, GPIO_MODE_AF_PP, GPIO_OSPEED_50MHZ, GPIO_PIN_TX);

    USART_CTL0(USARTx) &= ~USART_CTL0_WL;

    USART_CTL0(USARTx) |= USART_WL_8BIT;
	
    USART_CTL0(USARTx) &= ~(USART_CTL0_PM | USART_CTL0_PCEN);

    USART_CTL0(USARTx) |= USART_PM_NONE;
	
    USART_CTL1(USARTx) &= ~USART_CTL1_STB;

    USART_CTL1(USARTx) |= USART_STB_1BIT;
	
    uclk = USARTX_CLOCK_FREQ();
    
    udiv = (uclk + CONFIG_TRANSPARENT_SERIAL_BAUD / 2U) / CONFIG_TRANSPARENT_SERIAL_BAUD;
    
    intdiv = udiv & 0xfff0U;
    
    fradiv = udiv & 0xfU;

    USART_BAUD(USARTx) = ((USART_BAUD_FRADIV | USART_BAUD_INTDIV) & (intdiv | fradiv));

    USART_CTL0(USARTx) &= ~(USART_CTL0_REN);

    USART_CTL0(USARTx) |= (USART_CTL0_REN & USART_RECEIVE_ENABLE);
		
    USART_CTL0(USARTx) &= ~(USART_CTL0_TEN);

    USART_CTL0(USARTx) |= (USART_CTL0_TEN & USART_TRANSMIT_ENABLE);
		
    USART_CTL0(USARTx) |= USART_CTL0_UEN;
		
	return;
}

// Event handler for reading uart bits
static uint_fast8_t
transparent_event(struct timer *timer)
{
    uint32_t tmpI = 0;

    struct transparent_s *t = container_of(timer, struct transparent_s, timer);

    t->timer.waketime += TRANSPARENT_POLLING_PERIOD_TICKS;

    if((t->flag & START_RX) == START_RX)
    {
        if(t->rxBuf.timeoutS > 0)
        {
            if((timer_read_time() - t->rxBuf.startTime) > timer_from_us(1000000))
            {
                t->rxBuf.startTime = timer_read_time();

                t->rxBuf.timeoutS--; 
            }
        }

        if((t->rxBuf.timeoutS == 0) && (t->rxBuf.startTime != 0) && ((timer_read_time() - t->rxBuf.startTime) > timer_from_us(t->rxBuf.timeoutUs)))
        {
            t->flag &= ~START_RX;
             
            t->flag |= RX_TIMEOUT;
             
            for(tmpI = 0; tmpI < t->rxBuf.expLen; tmpI++)
            {        
                t->rxBuf.buf[tmpI] = 0;
            }

            t->rxBuf.dataIndx = 0;
             
            t->rxBuf.expLen = 0;
                
            t->rxBuf.startTime = 0;
                
            t->rxBuf.timeoutS = 0;
                
            t->rxBuf.timeoutUs = 0;

	        sched_wake_task(&transparent_wake);
            //设置超时状态，并向上位机反馈
            return SF_DONE; 
        }
         
        if(RESET != (USART_REG_VAL(USARTx, USART_FLAG_RBNE) & BIT(USART_BIT_POS(USART_FLAG_RBNE))))
        {
            t->rxBuf.buf[t->rxBuf.dataIndx] = (uint16_t)(GET_BITS(USART_DATA(USARTx), 0U, 8U));
                
            if(t->rxBuf.dataIndx == 2)
            {
                t->rxBuf.expLen = t->rxBuf.buf[t->rxBuf.dataIndx] + 3;
                //防止数据太长，溢出导致系统异常
                if(t->rxBuf.expLen > TRANSPARENT_DATA_LEN_MAX)
                {
                    t->rxBuf.dataIndx = 0;
                     
                    t->rxBuf.expLen = 0;
                        
                    t->rxBuf.startTime = 0;
                        
                    t->rxBuf.timeoutS = 0;
                    
                    t->rxBuf.timeoutUs = 0;
                        
                    t->flag = 0;
                        
                    t->flag |= RX_TIMEOUT;

	                sched_wake_task(&transparent_wake);

                    return SF_DONE; 
                }
            }
                
            t->rxBuf.dataIndx++;
                
            t->rxBuf.startTime = timer_read_time();
                
            if((t->rxBuf.expLen != 0) && (t->rxBuf.dataIndx >= t->rxBuf.expLen))
            {
                t->flag &= ~START_RX;
                 
                t->flag |= START_REPORT;
                    
	            sched_wake_task(&transparent_wake);
                 
                return SF_DONE;
            }
        }
    }

    if((t->flag & START_TX) == START_TX)
    {
        if(RESET != (USART_REG_VAL(USARTx, USART_FLAG_TBE) & BIT(USART_BIT_POS(USART_FLAG_TBE))))
        {
            USART_DATA(USARTx) = USART_DATA_DATA & (uint32_t)(t->txBuf.buf[t->txBuf.dataIndx]);
                
            t->txBuf.dataIndx++;
                
            if(t->txBuf.dataIndx >= t->txBuf.expLen)
            {
                t->flag &= ~START_TX;
                 
                t->rxBuf.startTime = timer_read_time();
                
                t->flag |= START_RX;
            }
        }
    }
        
    return SF_RESCHEDULE;
}

void
command_config_transparent(uint32_t *args)
{
    struct transparent_s *t = oid_alloc(args[0], command_config_transparent, sizeof(*t)); 

    t->timer.func = transparent_event;
     
    t->txBuf.buf = txBuf;
        
    t->txBuf.dataIndx = 0;
        
    t->txBuf.expLen = 0;
     
    t->rxBuf.buf = rxBuf;
        
    t->rxBuf.dataIndx = 0;
        
    t->rxBuf.expLen = 0;
        
    t->flag = 0;
        
    usart_init();
        
    return;
}

DECL_COMMAND(command_config_transparent,"config_transparent oid=%c");

void
command_transparent_send(uint32_t *args)
{
    struct transparent_s *t = oid_lookup(args[0], command_config_transparent);

    uint8_t *write = (uint8_t*)0;

    if ((t->flag & START_TX) || (t->flag & START_RX))
    {
        return;
    }

    write = command_decode_ptr(args[2]);

    t->txBuf.expLen = args[1];
    
    if(args[3] > 2500)
    {
        //转换成秒
        t->rxBuf.timeoutS = args[3] / 1000;
        //剩余时间，转换成us
        t->rxBuf.timeoutUs = args[3] % 1000 * 1000;
    }
    else
    {
        t->rxBuf.timeoutS = 0;

        t->rxBuf.timeoutUs = args[3] * 1000;
    }

    if(args[1] > TRANSPARENT_DATA_LEN_MAX)
    {
        shutdown("data is too long");
    }

    t->rxBuf.startTime = 0;

    t->txBuf.dataIndx = 0;

    memcpy(t->txBuf.buf, write, t->txBuf.expLen);
    
    irq_disable();

    t->timer.waketime = timer_read_time() + timer_from_us(200);

    //启动发送
    t->flag |= START_TX;
                
    sched_add_timer(&t->timer);

    irq_enable();
    
    return; 
}

DECL_COMMAND(command_transparent_send, "transparent_send oid=%c write=%*s timeout_ms=%u");

// Report completed response message back to host
void
transparent_task(void)
{
    uint8_t oid;

    uint32_t tmpI = 0;

    struct transparent_s *t;

    if (!sched_check_wake(&transparent_wake))
    {
        return;
    }
     
    foreach_oid(oid, t, command_config_transparent) 
    {
        if(t->flag & RX_TIMEOUT)
        {
            irq_disable();
             
            t->flag &= ~RX_TIMEOUT;
             
            irq_enable();
             
            t->rxBuf.expLen = 0; 
        }
        else if(t->flag & START_REPORT)
        {
            irq_disable();
             
            t->flag &= ~START_REPORT;
             
            irq_enable();
        }
        else
        {
        }

        sendf("transparent_response oid=%c read=%*s", oid, t->rxBuf.expLen,t->rxBuf.buf);
        
        for(tmpI = 0; tmpI < t->rxBuf.expLen; tmpI++)
        {        
            t->rxBuf.buf[tmpI] = 0;
        }
     
        t->txBuf.buf = txBuf;
            
        t->txBuf.dataIndx = 0;
            
        t->txBuf.expLen = 0;
         
        t->rxBuf.buf = rxBuf;
            
        t->rxBuf.dataIndx = 0;
            
        t->rxBuf.expLen = 0;
            
        t->flag = 0;
         
        irq_disable();
            
        sched_del_timer(&t->timer);
         
        irq_enable();
    }
     
    return;
}

DECL_TASK(transparent_task);

#endif

