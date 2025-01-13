//
// main.cpp
// zed-open-capture-mac
//
// Created by Christian Bator on 01/10/2025
//

#include "../include/zed_video_capture.hpp"
#include <opencv2/opencv.hpp>

using namespace std;
using namespace zed;

void showYUVVideo(string windowName)
{
    size_t height = 720;
    size_t width = 2560;

    VideoCapture videoCapture;
    videoCapture.open(YUV);

    cv::Mat yuvFrame(height, width, CV_8UC2);
    cv::Mat bgrFrame(height, width, CV_8UC3);

    videoCapture.start([&yuvFrame, &bgrFrame, windowName](uint8_t *data, size_t height, size_t width, size_t channels) {
        std::memcpy(yuvFrame.data, data, height * width * channels);

        cv::cvtColor(yuvFrame, bgrFrame, cv::COLOR_YUV2BGR_YUYV);

        cv::imshow(windowName, bgrFrame);
    });

    while (true) {
        cv::waitKey(1);
    }
}

void showGreyscaleVideo(string windowName)
{
    size_t height = 720;
    size_t width = 2560;

    VideoCapture videoCapture;
    videoCapture.open(GREYSCALE);

    cv::Mat greyscaleFrame(height, width, CV_8UC1);

    videoCapture.start([&greyscaleFrame, windowName](uint8_t *data, size_t height, size_t width, size_t channels) {
        std::memcpy(greyscaleFrame.data, data, height * width * channels);
        cv::imshow(windowName, greyscaleFrame);
    });

    while (true) {
        cv::waitKey(1);
    }
}

void showRGBVideo(string windowName)
{
    size_t height = 720;
    size_t width = 2560;

    VideoCapture videoCapture;
    videoCapture.open(RGB);

    cv::Mat rgbFrame(height, width, CV_8UC3);
    cv::Mat bgrFrame(height, width, CV_8UC3);

    videoCapture.start([&rgbFrame, &bgrFrame, windowName](uint8_t *data, size_t height, size_t width, size_t channels) {
        memcpy(rgbFrame.data, data, height * width * channels);

        cv::cvtColor(rgbFrame, bgrFrame, cv::COLOR_RGB2BGR);

        cv::imshow("ZED", bgrFrame);
    });

    while (true) {
        cv::waitKey(1);
    }
}

int main(int argc, const char *argv[])
{
    string windowName = "ZED";
    cv::namedWindow(windowName);

    // YUV example
    showYUVVideo(windowName);

    // Greyscale example
    // showGreyscaleVideo(windowName);

    // RGB example
    // showRGBVideo(windowName);

    return 0;
}
