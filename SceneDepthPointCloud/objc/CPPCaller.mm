#import "CPPCaller.h"
#include "Profiler.hpp"
#include "mtlpp.hpp"
#include "BufferPreprocessor.hpp"
#include <memory>

@interface CPPCaller()
@property (readonly) std::shared_ptr<BufferPreprocessor> bufferPreprocessor;
@end



@implementation CPPCaller

- (id)init {
   if( self = [super init] ) {
	   
	   auto deleter = [](auto p) {
		   std::cout << "____________________~BufferPreprocessor" << std::endl;
		   delete p;
	   };
	   _bufferPreprocessor = std::shared_ptr<BufferPreprocessor>(new BufferPreprocessor, deleter);
//	   _bufferPreprocessor = std::make_shared<BufferPreprocessor>();
   }
   
   return self;
}


-(void) show_buffer:(id<MTLBuffer>)buffer {
	showBufferCPP( ns::Handle{(__bridge void*)buffer} );
}

-(void) preprocessPointChunk:(id<MTLBuffer>)points {
	_bufferPreprocessor->newPortion( ns::Handle{(__bridge void*)points} );
}

-(void) triangulate {
	_bufferPreprocessor->triangulate();
}

-(void) separate {
	_bufferPreprocessor->separate();
}

-(void) findTtransformCoordinateSystem {
	_bufferPreprocessor->findTransformCS();
}

-(void) polishFoot {
	_bufferPreprocessor->polishFoot();
}

-(float) getFloorShift {
	return _bufferPreprocessor->getFloorHeight();
}

// depricated
-(float) getAngle {
	auto direction = _bufferPreprocessor->getAxesDir(0);
	return acos(direction.x());
}

-(float) getXYO:(int)component {
	auto xyo = _bufferPreprocessor->getXAxesOrigin();
	return xyo[component];
}

-(float) getDirection:(int)axes
					 :(int)component {
	
	auto dir = _bufferPreprocessor->getAxesDir(axes);
	return dir[component];
}

-(int) getIndexBuffer:(id<MTLBuffer>)indexBuffer
					 :(unsigned int)type {
	return _bufferPreprocessor->writeFaces( ns::Handle{(__bridge void*)indexBuffer}, type);
}

-(int) getVertexBuffer:(id<MTLBuffer>)pointBuffer {
	return _bufferPreprocessor->writeCoords( ns::Handle{(__bridge void*)pointBuffer}, true );
}

-(int) getPointCloudBuffer:(id<MTLBuffer>)pointBuffer {
	return _bufferPreprocessor->writeCoords( ns::Handle{(__bridge void*)pointBuffer}, false );
}

@end
