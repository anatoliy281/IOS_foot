#ifndef func_hpp
#define func_hpp

#include "mtlpp.hpp"
#include <chrono>
#include <utility>
#include <vector>
#include <string>
#include <exception>
#include <iostream>

//void testCall();

void showBufferCPP(mtlpp::Buffer buffer);

//class ProfilerCallError {
//private:
//	std::string description;
//public:
//	ProfilerCallError(const std::string& errorTimeDescription) : description {errorTimeDescription} {};
//	ProfilerCallError() = delete;
//	ProfilerCallError(const ProfilerCallError& e) = delete;
//	ProfilerCallError& operator=(const ProfilerCallError& e) = delete;
//	~ProfilerCallError() = default;
//
//	const std::string& describe() const {
//		return description;
//	}
//};

class Profiler final {
private:
	using ClockType = std::chrono::steady_clock;
	using CTP = ClockType::time_point;
	using DescrPair = std::pair<std::string,CTP>;
	using TimeMeasures = std::vector<DescrPair>;
	TimeMeasures measuredPoints;
	std::string caption;
public:
	Profiler(const std::string& profilerCaption);
	~Profiler() = default;
	Profiler(const Profiler& p) = delete;
	Profiler& operator=(const Profiler& p) = delete;
	
	int intervalCount() const;
	void measure(const std::string& intervalDescription = "");
	void reset();
	std::string showTimeIntervals() const;
};


std::ostream& operator<<(std::ostream& os, const Profiler& profiler);


//void triangulate();

//void triangulate(mtlpp::Buffer pointBuffer, mtlpp::Buffer indexBuffer);

#endif /* func_hpp */
