//
// zed_calibration_data.cpp
// zed-open-capture-mac
//
// Created by Christian Bator on 01/31/2025
//

#include "../include/zed_calibration_data.h"
#include <curl/curl.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>

using namespace std;
using namespace filesystem;

namespace zed {

#pragma mark - Public

    void CalibrationData::load(const string& serialNumber) {
        string numericSerialNumber = removeNonNumeric(serialNumber);
        path filepath = createFilepath(numericSerialNumber);

        if (!exists(filepath)) {
            cout << "Calibration data not found for " << serialNumber << ", downloading..." << endl;
            string url = "https://www.stereolabs.com/developers/calib/?SN=" + numericSerialNumber;
            downloadFile(url, filepath);
        }

        ifstream file(filepath);

        if (!file.is_open()) {
            throw runtime_error(format("Unable to open file: {}", filepath.string()));
        }

        string line, currentSection;
        while (getline(file, line)) {
            trim(line);

            // Ignore empty lines and comments (lines starting with ';' or '#')
            if (line.empty() || line[0] == ';' || line[0] == '#') {
                continue;
            }

            // Check for section headers
            if (line[0] == '[' && line[line.size() - 1] == ']') {
                currentSection = line.substr(1, line.size() - 2);
            }
            else {
                // Parse key=value pairs
                size_t pos = line.find('=');
                if (pos != string::npos) {
                    string key = line.substr(0, pos);
                    trim(key);

                    string value = line.substr(pos + 1);
                    trim(value);

                    size_t pos;
                    int intValue = stoi(value, &pos);

                    if (pos == value.size()) {
                        data[currentSection][key] = intValue;
                        continue;
                    }

                    float floatValue = stof(value, &pos);

                    if (pos == value.size()) {
                        data[currentSection][key] = floatValue;
                        continue;
                    }

                    cerr << "Unsupported value: " << value << " for key: " << key << endl;
                }
            }
        }

        file.close();
    }

    string CalibrationData::toString() {
        stringstream result;

        for (const auto& outerPair : data) {
            result << "\n[" << outerPair.first << "]" << endl;

            for (const auto& innerPair : outerPair.second) {
                result << innerPair.first << " = ";
                visit([&result](const auto& val) { result << val; }, innerPair.second);
                result << endl;
            }
        }

        return result.str();
    }

    string CalibrationData::calibrationString(StereoDimensions stereoDimensions) {
        switch (stereoDimensions.width / 2) {
            case 2208:
                return "2K";
            case 1920:
                return "FHD";
            case 1280:
                return "HD";
            case 672:
                return "VGA";
            default:
                throw runtime_error("Unimplemented CalibrationData::calibrationString() for StereoDimensions: " + stereoDimensions.toString());
        }
    }

#pragma mark - Private

    path CalibrationData::createFilepath(const string& numericSerialNumber) {
        const char* homeDirectory = getenv("HOME");
        if (!homeDirectory) {
            throw runtime_error("Unable to locate home directory");
        }

        path calibrationDataDirectory = path(homeDirectory) / ".stereolabs" / "calibration";

        if (!exists(calibrationDataDirectory)) {
            if (!create_directories(calibrationDataDirectory)) {
                throw runtime_error(format("Failed to create directory: {}", calibrationDataDirectory.string()));
            }
        }

        string filename = "SN" + numericSerialNumber + ".conf";
        path filepath = calibrationDataDirectory / filename;

        return filepath;
    }

    void CalibrationData::downloadFile(const string& url, const path& filepath) {
        curl_global_init(CURL_GLOBAL_DEFAULT);
        CURL* curl = curl_easy_init();

        if (!curl) {
            throw runtime_error("Failed to initialize curl");
        }

        ofstream outFile(filepath, ios::binary);

        if (!outFile.is_open()) {
            throw runtime_error(format("Failed to open file for writing: {}", filepath.string()));
        }

        curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, writeCallback);
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, &outFile);

        CURLcode res = curl_easy_perform(curl);

        if (res != CURLE_OK) {
            throw runtime_error(format("Failed to open file for writing: {}", filepath.string()));
        }
        else {
            cout << "Successfully downloaded calibration data to " << filepath.string() << endl;
        }

        outFile.close();

        curl_easy_cleanup(curl);
        curl_global_cleanup();
    }

    size_t CalibrationData::writeCallback(void* contents, size_t size, size_t nmemb, void* userp) {
        ofstream* outFile = static_cast<ofstream*>(userp);
        size_t totalSize = size * nmemb;
        outFile->write(static_cast<char*>(contents), totalSize);
        return totalSize;
    }

    void CalibrationData::trim(string& str) {
        size_t start = str.find_first_not_of(" \t");
        size_t end = str.find_last_not_of(" \t");
        if (start != string::npos && end != string::npos) {
            str = str.substr(start, end - start + 1);
        }
        else {
            str.clear();
        }
    }

    string CalibrationData::removeNonNumeric(const string& input) {
        string result;
        for (char ch : input) {
            if (isdigit(ch)) {
                result.push_back(ch);
            }
        }

        return result;
    }
};
