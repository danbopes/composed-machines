CXX      ?= g++
CXXFLAGS ?= -O2 -march=native -std=c++17 -Wall -Wextra

model: model.cpp
	$(CXX) $(CXXFLAGS) -o $@ $<

clean:
	rm -f model

.PHONY: clean
