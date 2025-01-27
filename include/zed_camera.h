//
// zed_camera.h
// zed-open-capture-mac
//
// Created by Christian Bator on 01/27/2025
//

#ifdef ZEDCAMERA_H
#define ZEDCAMERA_H

namespace zed {

    struct CameraImpl;

    class Camera {

    private:
        CameraImpl* impl;

    public:
        Camera();
        ~Camera();

        static Camera first();
    };

}

#endif
