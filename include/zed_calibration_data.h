//
// zed_calibration_data.h
// zed-open-capture-mac
//
// Created by Christian Bator on 01/31/2025
//

#ifndef ZED_CALIBRATION_DATA
#define ZED_CALIBRATION_DATA

#include "zed_video_capture_format.h"
#include <filesystem>
#include <map>

using namespace std;
using namespace filesystem;

namespace zed {

    class CalibrationData {

    public:
        // Loads calibration data for a given device serial number (downloading if necessary)
        void load(const string& serialNumber);

        // Gets a calibration parameter for section and key
        template <typename T> T get(const string& section, const string& key) {
            return std::get<T>(data[section][key]);
        }

        // String representatin of all calibration parameters
        string toString();

        // Returns the string suffix to query for resolution-specific calibration parameters
        string calibrationString(StereoDimensions stereoDimensions);

    private:
        // Data map of the form: [Section: [Key: Value]]
        map<string, map<string, variant<int, float>>> data;

        // Creates filepath to ~/.stereolabs/calibration/SN<numericSerialNumber>.conf
        path createFilepath(const string& numericSerialNumber);

        // Downloads calibration data from the given url and save it at the given filepath
        void downloadFile(const string& url, const path& filepath);

        // Curl write callback for saving data
        static size_t writeCallback(void* contents, size_t size, size_t nmemb, void* userp);

        // Trims leading and trailing whitespaces
        void trim(string& str);

        // Removes non-numeric characters from string
        string removeNonNumeric(const std::string& input);
    };
}

#endif
