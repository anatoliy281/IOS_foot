#import <Foundation/Foundation.h>
#import <Metal/MTLBuffer.h>

NS_ASSUME_NONNULL_BEGIN

@interface CPPCaller : NSObject

-(void) show_buffer:(id<MTLBuffer>)buffer;

-(void) preprocessPointChunk:(id<MTLBuffer>)points;

-(int) triangulate:(id<MTLBuffer>)pointBuffer
				   :(id<MTLBuffer>)indexBuffer;

@end

NS_ASSUME_NONNULL_END
