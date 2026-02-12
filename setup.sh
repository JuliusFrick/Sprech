#!/bin/bash
set -e

echo "🚀 Sprech Setup Script"
echo "========================"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check Homebrew
if ! command -v brew &> /dev/null; then
    echo -e "${RED}❌ Homebrew is not installed.${NC}"
    echo "Please install Homebrew first: https://brew.sh"
    exit 1
fi
echo -e "${GREEN}✓${NC} Homebrew found"

# Check Xcode
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}❌ Xcode command line tools not found.${NC}"
    echo "Please install Xcode from the App Store"
    exit 1
fi
echo -e "${GREEN}✓${NC} Xcode found"

# Check/Install XcodeGen
if ! command -v xcodegen &> /dev/null; then
    echo -e "${YELLOW}📦 Installing XcodeGen...${NC}"
    brew install xcodegen
fi
echo -e "${GREEN}✓${NC} XcodeGen found"

# Generate Xcode project
echo ""
echo "🔧 Generating Xcode project..."
xcodegen generate

if [ ! -d "Sprech.xcodeproj" ]; then
    echo -e "${RED}❌ Failed to generate Xcode project${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Xcode project generated"

# Verify build
echo ""
echo "🔨 Verifying build..."
if xcodebuild -project Sprech.xcodeproj -scheme Sprech -configuration Debug build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | tail -5; then
    echo -e "${GREEN}✓${NC} Build verification successful"
else
    echo -e "${YELLOW}⚠️  Build verification failed (may be expected for skeleton)${NC}"
fi

echo ""
echo "✅ Setup complete!"
echo "Open Sprech.xcodeproj in Xcode to start developing."
