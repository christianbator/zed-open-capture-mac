//
// main.cpp
// zed-open-capture-mac
//
// Created by Christian Bator on 01/10/2025
//

#include "../include/zed_video_capture.hpp"
#include <opencv2/highgui.hpp>
#include <opencv2/opencv.hpp>

using namespace std;
using namespace zed;

int main(int argc, const char *argv[])
{
    try {
        size_t height = 720;
        size_t width = 2560;

        cv::Mat frameBGRA(height, width, CV_8UC4);

        auto closure = [&frameBGRA](uint8_t* data, size_t height, size_t width, size_t channels) {
            std::memcpy(frameBGRA.data, data, height * width * 4);
            cv::imshow("ZED", frameBGRA);
        };

        VideoCapture videoCapture = VideoCapture(BGRA);
        videoCapture.start(closure);

        cv::namedWindow("ZED");

        while (true) {
            cv::waitKey(1);
        }
    }
    catch (...) {
        return 1;
    }

    return 0;
}
