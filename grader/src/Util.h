#pragma once

#include <Poco/Path.h>
#include <Poco/StringTokenizer.h>
#include <Poco/Util/AbstractConfiguration.h>
#include <yaml-cpp/yaml.h>

namespace Util {

Poco::Path expandRelativePath(const Poco::Path& rootFilePath, const std::string& relPath);
bool isWritableDirectory(const Poco::Path& path);

class YAMLConfiguration : public Poco::Util::AbstractConfiguration {
    std::string _filePath;
    YAML::Node _root;

public:
    void load(const std::string& path);

protected:
    bool getRaw(const std::string& key, std::string& value) const override;
    void setRaw(const std::string& key, const std::string& value) override;
    void enumerate(const std::string& key, Keys& range) const;
};

} // namespace Util