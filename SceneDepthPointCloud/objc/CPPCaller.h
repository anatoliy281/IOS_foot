#import <Foundation/Foundation.h>
#import <Metal/MTLBuffer.h>

NS_ASSUME_NONNULL_BEGIN

@interface CPPCaller : NSObject

-(void) show_buffer:(id<MTLBuffer>)buffer;

-(void) preprocessPointChunk:(id<MTLBuffer>)points;

-(int) triangulate:(id<MTLBuffer>)indexBuffer;

-(int) getVertexBuffer:(id<MTLBuffer>)pointBuffer;

@end

NS_ASSUME_NONNULL_END
