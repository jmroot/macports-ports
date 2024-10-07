#include <fcntl.h>
#include <stdio.h>
#include <sys/errno.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <unistd.h>

int main(int argc, char *argv[])
{
    off_t seekpos = 0;

    if (argc < 2) {
        printf("usage: %s file\n", argv[0]);
        return 1;
    }

    int fd = open(argv[1], O_RDONLY);
    if (fd < 0) {
        perror("open");
        return 1;
    }

    seekpos = lseek(fd, 0, SEEK_SET);

    unsigned char buf[4096];
    ssize_t nread;
    while ((nread = read(fd, &buf, 4096)) != 0) {
        if (nread == -1 && errno != EAGAIN && errno != EINTR) {
            perror("read");
            break;
        }
    }

    seekpos = lseek(fd, 0, SEEK_HOLE);
    printf("SEEK_HOLE: seekpos = %lld\n", seekpos);
    seekpos = lseek(fd, 0, SEEK_DATA);
    printf("SEEK_DATA: seekpos = %lld\n", seekpos);
    seekpos = lseek(fd, 0, SEEK_END);
    printf("SEEK_END: seekpos = %lld\n", seekpos);

    close(fd);
    return 0;
}
