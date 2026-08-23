#ifndef C_SMC_H
#define C_SMC_H

#include <stdint.h>

// ---------------------------------------------------------------------------
// AppleSMC user-client interface.
//
// Unlike the HID sensor hub, this uses a *public* IOKit user client
// ("AppleSMC" service, struct method selector 2), but the struct layout and
// selectors are undocumented — known from Apple's old PowerManagement open
// source and used by every monitoring tool (Stats, iStat, TG Pro, mactop).
//
// On Apple Silicon the SMC exposes extra temperature keys the HID hub does
// not: GPU clusters, CPU clusters, chassis/skin ("Ts…"), airflow ("Ta…").
// ---------------------------------------------------------------------------

typedef struct {
    uint8_t  major;
    uint8_t  minor;
    uint8_t  build;
    uint8_t  reserved;
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;        // fourcc, e.g. 'flt '
    uint8_t  dataAttributes;
} SMCKeyInfoData;

// 80 bytes with natural alignment — must match the kernel's expectation.
typedef struct {
    uint32_t       key;       // fourcc, e.g. 'Tg0G'
    SMCVersion     vers;
    SMCPLimitData  pLimitData;
    SMCKeyInfoData keyInfo;
    uint8_t        result;    // 0 = success, 132 = key not found
    uint8_t        status;
    uint8_t        data8;     // sub-command selector (see below)
    uint32_t       data32;
    uint8_t        bytes[32]; // value payload
} SMCParamStruct;

// IOConnectCallStructMethod selector:
#define kSMCHandleYPCEvent  2

// data8 sub-commands:
#define kSMCReadKey         5
#define kSMCGetKeyFromIndex 8
#define kSMCGetKeyInfo      9

#endif /* C_SMC_H */
