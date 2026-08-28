/* Wake a legacy libcp_mirror server blocked in accept(5900).
 *
 * Removing ARMED stops its outer loop, but QNX accept() has no timeout in the
 * installed older hook.  One loopback connect followed by close makes that
 * thread leave handshake/accept and release the port.  Loaded into /bin/sleep
 * only during B3 preflight; no process remains afterward.
 */
typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;

struct in_addr { u32 s_addr; };
struct sockaddr { u8 sa_len; u8 sa_family; char sa_data[14]; };
struct sockaddr_in {
    u8 sin_len;
    u8 sin_family;
    u16 sin_port;
    struct in_addr sin_addr;
    char sin_zero[8];
};

extern int socket(int, int, int);
extern int connect(int, const struct sockaddr *, int);
extern int close(int);
extern u16 htons(u16);

#define AF_INET 2
#define SOCK_STREAM 1
#define RFB_PORT 5900

static void port_waker_init(void) __attribute__((constructor));
static void port_waker_init(void) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address;
    int i;
    if (fd < 0) return;
    for (i = 0; i < (int)sizeof(address); ++i) ((u8 *)&address)[i] = 0;
    address.sin_len = (u8)sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons(RFB_PORT);
    address.sin_addr.s_addr = 0x0100007fU;
    (void)connect(fd, (const struct sockaddr *)&address, (int)sizeof(address));
    close(fd);
}
