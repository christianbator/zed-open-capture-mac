<h1 align="center">
  ZED Open Capture (macOS)
</h1>

<h4 align="center">A macOS camera and sensor capture API for the <a href="https://www.stereolabs.com/products/zed-2">ZED 2i, ZED 2, and ZED Mini</a> stereo cameras</h4>
<h5 align="center">*** not compatible with GMSL2 devices: <a href="https://www.stereolabs.com/products/zed-x">ZED X, ZED X Mini, and ZED X One</a> ***</h5>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#install">Install</a> •
  <a href="#run">Run</a> • 
  <a href="#calibration">Calibration</a> •
  <a href="#examples">Examples</a> •
  <a href="#related">Related</a>
</p>
<br>

## Features

- Video data capture
    - [x] YUV 4:2:2 (native camera format)
    - [x] Greyscale
    - [x] RGB (hardware-accelerated conversion)
    - [x] BGR (hardware-accelerated conversion)
- Resolution control
    - [x] HD2K: 2208 x 1242 (15 fps)
    - [x] HD1080: 1920 x 1080 (15, 30 fps)
    - [x] HD720: 1280 x 720 (15, 30, 60 fps)
    - [x] VGA: 672 x 376 (15, 30, 60, 100 fps)
- Camera info
    - [x] Name
    - [x] Unique connection ID
    - [x] Serial number
    - [x] Calibration data
- Camera control
    - [x] LED on / off
    - [x] Brightness
    - [x] Contrast
    - [x] Hue
    - [x] Saturation
    - [x] Sharpness
    - [ ] Gamma
    - [ ] Gain
    - [ ] Exposure
    - [x] White balance temperature
    - [x] Auto white balance temperature
- Sensor data capture
    - [ ] 6-DOF IMU (3-DOF accelerometer & 3-DOF gyroscope)
    - [ ] 3-DOF Magnetometer (ZED 2 & ZED 2i)
    - [ ] Barometer (ZED 2 & ZED 2i)
    - [ ] Temperature (ZED 2 & ZED 2i)
    - [ ] Video and sensor data synchronization

### Description

The ZED Open Capture library is a macOS library for low-level camera and sensor capture for the ZED stereo camera family.

The library provides methods to access raw video frames, calibration data, camera controls, and raw data from the USB 3 camera sensors. A synchronization mechanism is provided to associate the correct sensor data with a particular video frame.

**Note:** The ZED SDK calibrates all output data, but here you're dealing with raw data. See <a href="#calibration">calibration</a> below for details about downloading and applying the calibration parameters to correct the camera data.

## Install

### Prerequisites

 * Stereolabs USB 3 Stereo camera: [ZED 2i](https://www.stereolabs.com/zed-2i/), [ZED 2](https://www.stereolabs.com/zed-2/), [ZED Mini](https://www.stereolabs.com/zed-mini/)
 * macOS (>= 15)
 * Clang (>= 19) (Xcode or Homebrew)
 * CMake (>= 3.31)
 * OpenCV (>= 4.10) (Optional: for examples) 

### Install prerequisites

- Install clang via Xcode
```zsh
xcode-select -install
```

- Install clang via Homebrew (optional)
```zsh
brew install llvm

# Add to ~/.zshrc to prefer homebrew clang
export PATH="/opt/homebrew/opt/llvm/bin:$PATH"
export CC=$(which clang)
export CXX=$(which clang++)
```

- Install CMake build system
```zsh
brew install cmake
```

- Install OpenCV to build the examples (optional)
```zsh
brew install opencv
```

### Clone the repository

```zsh
git clone https://github.com/christianbator/zed-open-capture-mac.git
cd zed-open-capture-mac
```

### Build the library

```zsh
cmake -B build
cmake --build build --parallel
sudo cmake --install build
```

### Install the library

```zsh
sudo cmake --install build
```

### Uninstall the library

```zsh
sudo rm -r /opt/stereolabs
```

## Run

### Video capture

Open the capture to find an attached ZED camera and initialize USB communcation. This is necessary before using any other methods on the VideoCapture instance:
```C++
// Include the header
#include "zed_video_capture.h"

// Create a video capture instance
VideoCapture videoCapture;

// Open the stream with a color space: YUV, GREYSCALE, RGB, or BGR
// (resolution defaults to HD2K and 15 fps)
videoCapture.open(RGB);

// Alternatively, open the stream with a specified resolution and frame rate
// (see `zed_video_capture.h` for available resolutions, frame rates, and color spaces)
videoCapture.open<HD720, FPS_60>(RGB);
```

Start the capture to begin processing frames:
```C++
// Start the capture, passing a closure or function that's invoked for each frame
videoCapture.start([](uint8_t *data, size_t height, size_t width, size_t channels) {
    //
    // `data` is an interleaved pixel buffer in the specified color space
    // `data` is (height * width * channels) bytes long
    //  
    // Process `data` here
    //
});

// Keep the process alive while processing frames
while (true) {
    // For example, with OpenCV:
    cv::waitKey(1);
}
```

You can stop the stream at any point and restart it later:
```c++
videoCapture.stop();
```

Close the capture when you're done to free resources and release all USB device handles:
```c++
videoCapture.close();
```

Camera controls with get, set, and reset functionality are available:
```c++
uint16_t brightness = videoCapture.getBrightness();

videoCapture.setBrightness(7);

uint16_t defaultBrightness = videoCapture.getDefaultBrightness();

videoCapture.resetBrightness();
```

### Sensor data

TODO...

#### Coordinate system

The given IMU and magnetometer data are expressed in the coordinate system shown below:

![](images/imu-axis.jpg)

## Calibration

You can load the factory calibration parameters for your particular camera from the StereoLabs servers using the supplied methods.

```c++
// Downloads calibration data to ~/.stereolabs/calibration and parses the parameters
CalibrationData calibrationData = videoCapture.getCalibrationData();

// View the calibration data:
cout << calibrationData.toString() << endl;

// Access parameters by section and key (specify the type: int or float)
float stereoBaseline = calibrationData.get<float>("STEREO", "Baseline");
cout << "Stereo Baseline = " << stereoBaseline << endl;
```

You can also pass a serial number to load the calibration data directly instead of using the convenience method above.
```c++
CalibrationData calibrationData;
calibrationData.load("<DEVICE_SERIAL_NUMBER>");
```

See the calibration example below for details about using the calibration data to rectify video frames.

## Examples

Make sure you've built and installed the library with:

```zsh
cmake -B build
cmake --build build --parallel
sudo cmake --install build
```

Then you can build the examples with:

```zsh
cd examples
cmake -B build
cmake --build build --parallel
```

The following examples are built:

- [video_stream](examples/video_stream.cpp)
    - Displays the connected ZED camera stream in the desired color space with OpenCV
    - Usage: `./build/video_stream (yuv | greyscale | rgb | bgr)`
- [camera_controls](examples/camera_controls.cpp)
    - Shows how to adjust camera controls and displays the stream with OpenCV
    - Usage: `./build/camera_controls`
- [calibration](examples/calibration.cpp)
    - Shows how to use camera calibration data to rectify frames with OpenCV
    - Usage: `./build/calibration`

## Related

- [Stereolabs](https://www.stereolabs.com)
- [ZED SDK](https://www.stereolabs.com/developers/)
