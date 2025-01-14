//
// opencv_video_stream.cpp
// zed-open-capture-mac
//
// Created by Christian Bator on 01/13/2025
//

#include <format>
#include "zed_video_capture.hpp"
#include <opencv2/opencv.hpp>

using namespace std;
using namespace zed;

//
// YUV
//
void showYUVVideo()
{
    string windowName = "ZED";
    cv::namedWindow(windowName);

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

//
// Greyscale
//
void showGreyscaleVideo()
{
    string windowName = "ZED";
    cv::namedWindow(windowName);

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

//
// RGB
//
void showRGBVideo()
{
    string windowName = "ZED";
    cv::namedWindow(windowName);

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

//
// Usage
//
int usageError(string error) {
    cerr << "> Error: " << error << endl;
    cerr << "> Usage: opencv_video_stream (yuv | greyscale | rgb)" << endl;

    return 2;
}

//
// Main
//
int main(int argc, const char *argv[])
{
    if (argc != 2) {
        return usageError("Too few arguments");
    }

    string formatArgument = argv[1];
    
    if (formatArgument == "yuv") {
        showYUVVideo();
    }
    else if (formatArgument == "greyscale") {
        showGreyscaleVideo();
    }
    else if (formatArgument == "rgb") {
        showRGBVideo();
    }
    else {
        return usageError(format("Invalid format '{}'", formatArgument));
    }
    
    return 0;
}
