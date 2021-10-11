#import <Foundation/Foundation.h>
#import <Metal/MTLBuffer.h>

NS_ASSUME_NONNULL_BEGIN

@interface CPPCaller : NSObject

- (id)init;

-(void) show_buffer:(id<MTLBuffer>)buffer;

-(void) preprocessPointChunk:(id<MTLBuffer>)points;

-(void) triangulate;

-(void) separate;

-(void) findTtransformCoordinateSystem;

-(void) polishFoot;

-(float) getFloorShift;

-(float) getXYO:(int)component;

-(float) getDirection:(int)axes
					 :(int)component;

-(int) getIndexBuffer:(id<MTLBuffer>)indexBuffer
					 :(unsigned int)type;

-(int) getVertexBuffer:(id<MTLBuffer>)pointBuffer;

-(int) getPointCloudBuffer:(id<MTLBuffer>)pointBuffer;

@end

NS_ASSUME_NONNULL_END
