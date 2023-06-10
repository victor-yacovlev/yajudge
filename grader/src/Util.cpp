#include "Util.h"

#include <Poco/StreamCopier.h>

#include <fstream>
#include <iostream>
#include <stack>

void Util::YAMLConfiguration::load(const std::string& path)
{
    _filePath = path;
    _root = YAML::LoadFile(path);
}

bool Util::YAMLConfiguration::getRaw(const std::string& key, std::string& value) const
{
    Poco::StringTokenizer parts(key, ".", Poco::StringTokenizer::TOK_TRIM);

    // YAML::Node overrides = operator, so push path entries into stack
    // and DO NOT try to use = operator
    std::stack<YAML::Node> path;
    path.push(_root);
    for (size_t i = 0; i < parts.count(); ++i) {
        const std::string& part = parts[i];
        path.push(path.top()[part]);
        if (!path.top().IsDefined()) {
            return false;
        }
    }

    value = path.top().as<std::string>();
    return true;
}

void Util::YAMLConfiguration::setRaw(const std::string& key, const std::string& value) { }

void Util::YAMLConfiguration::enumerate(const std::string& key, Keys& range) const
{
    Poco::StringTokenizer parts(key, ".", Poco::StringTokenizer::TOK_TRIM);

    // YAML::Node overrides = operator, so push path entries into stack
    // and DO NOT try to use = operator
    std::stack<YAML::Node> path;
    path.push(_root);
    for (size_t i = 0; i < parts.count(); ++i) {
        const std::string& part = parts[i];
        path.push(path.top()[part]);
        if (!path.top().IsDefined()) {
            return;
        }
    }

    for (auto it = path.top().begin(); it != path.top().end(); ++it) {
        range.push_back(it->first.as<std::string>());
    }
}
