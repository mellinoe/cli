#!/usr/bin/env bash
#
# Copyright (c) .NET Foundation and contributors. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# OSX Shared Assembly Packaging Script
# Tested on OSX 10.10.5 

set -e
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

source "$DIR/../../common/_common.sh"

if [ "$(uname)" != "Darwin" ]; then
    error "PKG build only supported on OSX"
    exit 1
fi

PACKAGING_ROOT="$REPOROOT/packaging/sharedframework/osx"

OUTPUT_DIR="$REPOROOT/artifacts"
INPUT_DIR="$REPOROOT/src/sharedframework/NETCoreApp/1.0.0"
PACKAGE_LAYOUT_DIR="$OUTPUT_DIR/osx_sharedframework_intermediate"
PACKAGE_OUTPUT_DIR="$OUTPUT_DIR/packages/sharedframework/osx"
SHARED_FRAMEWORK_INSTALL_DIR="/usr/local/share/dotnet"

SHARED_FRAMEWORK_PKG_PACKAGE_NAME="dotnet-sharedframework-1.0.0"
SHARED_FRAMEWORK_PKG_PACKAGE_ID="com.microsoft.dotnet.sharedframework.pkg.dotnet-osx-x64"

execute_build(){
    create_empty_pkg_layout
    copy_files_to_pkg_layout
    create_pkg_package
}

create_empty_pkg_layout(){
    header "Creating empty pkg package layout"

    rm -rf "$PACKAGE_LAYOUT_DIR"
    mkdir -p "$PACKAGE_LAYOUT_DIR"
    mkdir -p "$PACKAGE_LAYOUT_DIR/package_root"
}

copy_files_to_pkg_layout(){
    header "Copying files to pkg layout"

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
    chmod -x "$PACKAGE_LAYOUT_DIR/package_root/shared/NETCoreApp/1.0.0/x64/"*.dylib
}

create_pkg_package(){
    header "Creating .pkg"
    mkdir -p "$PACKAGE_OUTPUT_DIR"

    pkgbuild --root $PACKAGE_LAYOUT_DIR/package_root \
        --version $DOTNET_CLI_VERSION \
        --identifier $SHARED_FRAMEWORK_PKG_PACKAGE_ID \
        --install-location $SHARED_FRAMEWORK_INSTALL_DIR \
        $PACKAGE_OUTPUT_DIR/$SHARED_FRAMEWORK_PKG_PACKAGE_NAME.pkg

    # Format the Distribution-Template file with current version number.
    cat $REPOROOT/packaging/sharedframework/osx/Distribution-Template.xml \
        | sed "/{VERSION}/s//1.0.0/g" \
        > $PACKAGE_OUTPUT_DIR/Formatted-Distribution.xml

    PRODUCT_PKG_NAME=dotnet-sharedframework-x64.1.0.0.pkg

    header "Creating Product .pkg"

    productbuild --version $DOTNET_CLI_VERSION \
        --identifier com.microsoft.dotnet.sharedframework \
        --package-path $PACKAGE_OUTPUT_DIR \
        --distribution $PACKAGE_OUTPUT_DIR/Formatted-Distribution.xml \
        $PACKAGE_OUTPUT_DIR/$PRODUCT_PKG_NAME
}

execute_build

# Publish
PKG_FILE=$(find $PACKAGE_OUTPUT_DIR -iname "*.pkg")
# $REPOROOT/scripts/publish/publish.sh $PKG_FILE
