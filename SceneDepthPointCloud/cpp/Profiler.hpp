#ifndef Profiler_hpp
#define Profiler_hpp

#include "mtlpp.hpp"
#include <chrono>
#include <utility>
#include <vector>
#include <string>
#include <exception>
#include <iostream>


void showBufferCPP(mtlpp::Buffer buffer);

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

#endif /* Profiler_hpp */
