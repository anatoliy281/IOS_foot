#import <Foundation/Foundation.h>
#import <Metal/MTLBuffer.h>

NS_ASSUME_NONNULL_BEGIN

@interface CPPCaller : NSObject
	-(void) call;

	-(void) show_buffer:(id<MTLBuffer>)buffer;

	-(void) triangulate;

//	-(void) triangulate:(id<MTLBuffer>)pointBuffer:
//						(id<MTLBuffer>)indexBuffer;


@end

NS_ASSUME_NONNULL_END
