#!/usr/bin/env bash
#
# Copyright (c) .NET Foundation and contributors. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# Debian Shared Assembly Packaging Script
# Currently Intended to build on ubuntu14.04

set -e
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

source "$DIR/../../common/_common.sh"

if [ "$OSNAME" != "ubuntu" ]; then
    error "Debian Package build only supported on Ubuntu"
    exit 1
fi

PACKAGING_ROOT="$REPOROOT/packaging/sharedframework/debian"
PACKAGING_TOOL_DIR="$REPOROOT/tools/DebianPackageTool"

OUTPUT_DIR="$REPOROOT/artifacts"
INPUT_DIR="$REPOROOT/src/sharedframework/NETCoreApp/1.0.0"
PACKAGE_LAYOUT_DIR="$OUTPUT_DIR/deb_sharedframework_intermediate"
PACKAGE_OUTPUT_DIR="$OUTPUT_DIR/packages/sharedframework/debian"

SHARED_FRAMEWORK_DEB_PACKAGE_NAME="dotnet-sharedframework-1.0.0"

execute_build(){
    create_empty_debian_layout
    copy_files_to_debian_layout
    create_debian_package
}

create_empty_debian_layout(){
    header "Creating empty debian package layout"

    rm -rf "$PACKAGE_LAYOUT_DIR"
    mkdir -p "$PACKAGE_LAYOUT_DIR"
    mkdir -p "$PACKAGE_LAYOUT_DIR/package_root"
}

copy_files_to_debian_layout(){
    header "Copying files to debian layout"

    # Publish runtime project to pick up all the framework bits.
    mkdir -p "$PACKAGE_LAYOUT_DIR/package_root/shared/NETCoreApp/1.0.0/x64"
    "$DOTNET_INSTALL_DIR/bin/dotnet" publish -o  "$PACKAGE_LAYOUT_DIR/package_root/shared/NETCoreApp/1.0.0/x64" "$INPUT_DIR/project.json"

    # The process of using dotnet publish as a way to deploy the contents of NETStandard.Library causes a few extra
    # files to be present in the output that we don't want to package. Remove them. Note that we keep the .deps file
    # as the loader will use this to understand what assets are in the shared framework.
    rm "$PACKAGE_LAYOUT_DIR/package_root/shared/NETCoreApp/1.0.0/x64/1.0.0"
    rm "$PACKAGE_LAYOUT_DIR/package_root/shared/NETCoreApp/1.0.0/x64/1.0.0.dll"
    rm "$PACKAGE_LAYOUT_DIR/package_root/shared/NETCoreApp/1.0.0/x64/1.0.0.pdb"
    mv "$PACKAGE_LAYOUT_DIR/package_root/shared/NETCoreApp/1.0.0/x64/1.0.0.deps" "$PACKAGE_LAYOUT_DIR/package_root/shared/NETCoreApp/1.0.0/x64/NETCoreApp.deps"

    # dotnet publish makes a bunch of stuff executable by default which doesn't need to be.
    chmod -x "$PACKAGE_LAYOUT_DIR/package_root/shared/NETCoreApp/1.0.0/x64/"*.deps
    chmod -x "$PACKAGE_LAYOUT_DIR/package_root/shared/NETCoreApp/1.0.0/x64/"*.dll
    chmod -x "$PACKAGE_LAYOUT_DIR/package_root/shared/NETCoreApp/1.0.0/x64/"*.so

    # Copy config file
    cp "$PACKAGING_ROOT/dotnet-sharedframework-1.0.0-debian_config.json" "$PACKAGE_LAYOUT_DIR/debian_config.json"
}

create_debian_package(){
    header "Packing .deb"

    mkdir -p "$PACKAGE_OUTPUT_DIR"

    "$PACKAGING_TOOL_DIR/package_tool" -i "$PACKAGE_LAYOUT_DIR" -o "$PACKAGE_OUTPUT_DIR" -v $DOTNET_CLI_VERSION -n $SHARED_FRAMEWORK_DEB_PACKAGE_NAME
}

execute_build

DEBIAN_FILE=$(find $PACKAGE_OUTPUT_DIR -iname "*.deb")

# Publish
$REPOROOT/scripts/publish/publish.sh $DEBIAN_FILE
