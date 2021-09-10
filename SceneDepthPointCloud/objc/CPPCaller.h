#import <Foundation/Foundation.h>
#import <Metal/MTLBuffer.h>

NS_ASSUME_NONNULL_BEGIN

@interface CPPCaller : NSObject
	-(void) call;

	-(void) show_buffer:(id<MTLBuffer>)buffer;

@end

NS_ASSUME_NONNULL_END
