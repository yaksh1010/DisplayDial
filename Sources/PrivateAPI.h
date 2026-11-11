// Private IOKit calls that send DDC/CI commands to an external monitor on Apple Silicon
// (the same ones MonitorControl and m1ddc use). Not App Store safe.
#import <CoreFoundation/CoreFoundation.h>
#import <IOKit/IOKitLib.h>

typedef CFTypeRef IOAVService;

extern IOAVService IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service) CF_RETURNS_RETAINED;
extern IOReturn IOAVServiceReadI2C(IOAVService service, uint32_t chipAddress, uint32_t offset,
                                   void *outputBuffer, uint32_t outputBufferSize);
extern IOReturn IOAVServiceWriteI2C(IOAVService service, uint32_t chipAddress, uint32_t dataAddress,
                                    void *inputBuffer, uint32_t inputBufferSize);
