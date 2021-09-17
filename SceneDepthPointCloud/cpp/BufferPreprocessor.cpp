#include "BufferPreprocessor.hpp"
#include <iostream>


BufferPreprocessor::BufferPreprocessor() {
	points.reserve(capacity);
	std::cout << "::BufferPreprocessor" << std::endl;
}

BufferPreprocessor::~BufferPreprocessor() {
	std::cout << "~BufferPreprocessor" << std::endl;
}

void BufferPreprocessor::newPortion(mtlpp::Buffer points) {
	
}

void BufferPreprocessor::triangulate(mtlpp::Buffer pointBuffer,
									 mtlpp::Buffer indexBuffer) const {
	
}
