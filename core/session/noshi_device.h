#ifndef NOSHI_DEVICE_H
#define NOSHI_DEVICE_H

/* the name the owner knows a device by, for the session list that telegram shows on every other client. hw.machine
   gives only "iPhone4,1", and the official clients send "iPhone 4S" */
const char *noshi_device_name(const char *machine);

#endif
