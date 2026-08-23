#ifndef C_PRIVATE_HID_H
#define C_PRIVATE_HID_H

#include <CoreFoundation/CoreFoundation.h>
#include "CSMC.h"

// ---------------------------------------------------------------------------
// Private IOHIDEventSystemClient API (implemented inside IOKit.framework).
// No public headers exist, so we declare the symbols ourselves.
// Same approach as Stats, Hot, mactop, iSMC.
//
// NOTE: private API => fine for notarized direct-download apps,
// but will NOT pass Mac App Store review.
// ---------------------------------------------------------------------------

typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDServiceClient     *IOHIDServiceClientRef;
typedef struct __IOHIDEvent             *IOHIDEventRef;

// Creates the event system client (Create rule: caller must release).
IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);

// Filters which HID services the client sees.
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client,
                                      CFDictionaryRef matching);

// Returns matched services. "Copy" naming => Swift imports this as a
// managed (+1) CFArray, ARC releases it automatically.
CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);

// Reads a property from a service, e.g. "Product". "Copy" naming =>
// managed by ARC on the Swift side.
CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service,
                                         CFStringRef property);

// Reads the latest event of a given type from a service.
// Returns an opaque pointer Swift can't manage: release with CPHIDReleaseEvent.
IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service,
                                          int64_t type,
                                          int32_t options,
                                          int64_t timestamp);

// Extracts a float field from an event.
double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Apple vendor usage page; usage 5 = temperature sensors.
#define kHIDPage_AppleVendor                    0xff00
#define kHIDUsage_AppleVendor_TemperatureSensor 0x0005

// Event type 15 = temperature.
#define kIOHIDEventTypeTemperature 15

// ---------------------------------------------------------------------------
// Swift-friendly helpers.
// Swift sees our typedefs as OpaquePointer (not CF objects) and bans direct
// CFRelease, so we release from C. Function-like macros don't import either,
// so the field base is a real function.
// ---------------------------------------------------------------------------

static inline int32_t CPHIDTemperatureField(void) {
    // IOHIDEventFieldBase(type) == (type << 16), offset 0 = current value.
    return (int32_t)(kIOHIDEventTypeTemperature << 16);
}

static inline void CPHIDReleaseClient(IOHIDEventSystemClientRef client) {
    if (client) CFRelease((CFTypeRef)client);
}

static inline void CPHIDReleaseEvent(IOHIDEventRef event) {
    if (event) CFRelease((CFTypeRef)event);
}

#endif /* C_PRIVATE_HID_H */
