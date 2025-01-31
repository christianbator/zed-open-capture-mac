//
// calibration.cpp
// zed-open-capture-mac
//
// Created by Christian Bator on 01/31/2025
//

#include "zed_video_capture.h"
#include <opencv2/opencv.hpp>

using namespace std;
using namespace zed;
using namespace cv;

//
// Calibration Initialization
//
void initializeCalibrationMatrices(CalibrationData& calibrationData,
    StereoDimensions stereoDimensions,
    Mat& mapLeftX,
    Mat& mapLeftY,
    Mat& mapRightX,
    Mat& mapRightY,
    Mat& cameraMatrixLeft,
    Mat& cameraMatrixRight) {

    //
    // Parse parameters
    //
    string resolutionString = calibrationData.calibrationString(stereoDimensions);
    Size imageSize = Size(stereoDimensions.width / 2, stereoDimensions.height);

    string stereoSection = "STEREO";

    // Translations
    float translations[3];
    translations[0] = calibrationData.get<float>(stereoSection, "Baseline");
    translations[1] = calibrationData.get<float>(stereoSection, "TY");
    translations[2] = calibrationData.get<float>(stereoSection, "TZ");

    // Rotations
    Mat R_zed = (Mat_<double>(1, 3) << calibrationData.get<float>(stereoSection, "RX_" + resolutionString),
        calibrationData.get<float>(stereoSection, "CV_" + resolutionString),
        calibrationData.get<float>(stereoSection, "RZ_" + resolutionString));

    // Left camera parameters
    string leftCamSection = "LEFT_CAM_" + resolutionString;
    float leftCamCX = calibrationData.get<float>(leftCamSection, "cx");
    float leftCamCY = calibrationData.get<float>(leftCamSection, "cy");
    float leftCamFX = calibrationData.get<float>(leftCamSection, "fx");
    float leftCamFY = calibrationData.get<float>(leftCamSection, "fy");
    float leftCamK1 = calibrationData.get<float>(leftCamSection, "k1");
    float leftCamK2 = calibrationData.get<float>(leftCamSection, "k2");
    float leftCamP1 = calibrationData.get<float>(leftCamSection, "p1");
    float leftCamP2 = calibrationData.get<float>(leftCamSection, "p2");
    float leftCamK3 = calibrationData.get<float>(leftCamSection, "k3");

    // Right camera parameters
    string rightCamSection = "RIGHT_CAM_" + resolutionString;
    float rightCamCX = calibrationData.get<float>(rightCamSection, "cx");
    float rightCamCY = calibrationData.get<float>(rightCamSection, "cy");
    float rightCamFX = calibrationData.get<float>(rightCamSection, "fx");
    float rightCamFY = calibrationData.get<float>(rightCamSection, "fy");
    float rightCamK1 = calibrationData.get<float>(rightCamSection, "k1");
    float rightCamK2 = calibrationData.get<float>(rightCamSection, "k2");
    float rightCamP1 = calibrationData.get<float>(rightCamSection, "p1");
    float rightCamP2 = calibrationData.get<float>(rightCamSection, "p2");
    float rightCamK3 = calibrationData.get<float>(rightCamSection, "k3");

    //
    // Calculate Matrices
    //
    Mat R;
    Rodrigues(R_zed, R);

    Mat distCoeffsLeft, distCoeffsRight;

    // Left
    cameraMatrixLeft = (Mat_<double>(3, 3) << leftCamFX, 0, leftCamCX, 0, leftCamFY, leftCamCY, 0, 0, 1);
    distCoeffsLeft = (Mat_<double>(5, 1) << leftCamK1, leftCamK2, leftCamP1, leftCamP2, leftCamK3);

    // Right
    cameraMatrixRight = (Mat_<double>(3, 3) << rightCamFX, 0, rightCamCX, 0, rightCamFY, rightCamCY, 0, 0, 1);
    distCoeffsRight = (Mat_<double>(5, 1) << rightCamK1, rightCamK2, rightCamP1, rightCamP2, rightCamK3);

    // Stereo
    Mat T = (Mat_<double>(3, 1) << translations[0], translations[1], translations[2]);

    Mat R1, R2, P1, P2, Q;
    stereoRectify(cameraMatrixLeft, distCoeffsLeft, cameraMatrixRight, distCoeffsRight, imageSize, R, T, R1, R2, P1, P2, Q, CALIB_ZERO_DISPARITY, 0, imageSize);

    // Precompute maps for remap()
    initUndistortRectifyMap(cameraMatrixLeft, distCoeffsLeft, R1, P1, imageSize, CV_32FC1, mapLeftX, mapLeftY);
    initUndistortRectifyMap(cameraMatrixRight, distCoeffsRight, R2, P2, imageSize, CV_32FC1, mapRightX, mapRightY);

    cameraMatrixLeft = P1;
    cameraMatrixRight = P2;
}

//
// Main
//
int main() {
    // Create VideoCapture
    zed::VideoCapture videoCapture;
    StereoDimensions stereoDimensions = videoCapture.open<HD720, FPS_30>(BGR);

    // Load calibration data
    CalibrationData calibrationData;
    calibrationData.load("37970291");

    // Initialize calibration matrices
    Mat mapLeftX, mapLeftY;
    Mat mapRightX, mapRightY;
    Mat cameraMatrixLeft, cameraMatrixRight;

    initializeCalibrationMatrices(calibrationData, stereoDimensions, mapLeftX, mapLeftY, mapRightX, mapRightY, cameraMatrixLeft, cameraMatrixRight);
    cout << "\nLeft Camera Matrix: \n" << cameraMatrixLeft << endl << endl;
    cout << "Right Camera Matrix: \n" << cameraMatrixRight << endl << endl;

    //
    // Visualize Raw & Rectified Frames
    //
    string rawWindowName = "Raw";
    namedWindow(rawWindowName);
    string rectifiedWindowName = "Rectified";
    namedWindow(rectifiedWindowName);
    moveWindow(rectifiedWindowName, 0, stereoDimensions.height / 2);

    Mat rawFrame(stereoDimensions.height, stereoDimensions.width, CV_8UC3);
    Mat rectifiedFrame(stereoDimensions.height, stereoDimensions.width, CV_8UC3);
    Mat leftRaw(stereoDimensions.height, stereoDimensions.width / 2, CV_8UC3);
    Mat leftRectified(stereoDimensions.height, stereoDimensions.width / 2, CV_8UC3);
    Mat rightRaw(stereoDimensions.height, stereoDimensions.width / 2, CV_8UC3);
    Mat rightRectified(stereoDimensions.height, stereoDimensions.width / 2, CV_8UC3);

    videoCapture.start([&rawFrame,
                           &rectifiedFrame,
                           &leftRaw,
                           &leftRectified,
                           &rightRaw,
                           &rightRectified,
                           &mapLeftX,
                           &mapLeftY,
                           &mapRightX,
                           &mapRightY,
                           rawWindowName,
                           rectifiedWindowName](uint8_t* data, size_t height, size_t width, size_t channels) {
        memcpy(rawFrame.data, data, height * width * channels);

        leftRaw = rawFrame(Rect(0, 0, width / 2, height));
        remap(leftRaw, leftRectified, mapLeftX, mapLeftY, INTER_LINEAR);

        rightRaw = rawFrame(Rect(width / 2, 0, width / 2, height));
        remap(rightRaw, rightRectified, mapRightX, mapRightY, INTER_LINEAR);

        hconcat(leftRectified, rightRectified, rectifiedFrame);

        imshow(rawWindowName, rawFrame);
        imshow(rectifiedWindowName, rectifiedFrame);
    });

    while (true) {
        int key = cv::waitKey(1);

        if (key == 27) {
            break;
        }
    }

    videoCapture.stop();
    videoCapture.close();

    return 0;
}
