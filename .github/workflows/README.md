# GitHub Workflows

This directory contains automated GitHub Actions workflows for building and releasing the Host Discovery Service.

## Available Workflows

### 1. `release.yml` - Multi-Architecture Release (Recommended)

**Purpose**: Builds and releases binaries for multiple architectures (amd64, arm64, armv7)

**Triggers**:
- Push tags matching `v*` (e.g., `v1.0.0`, `v2.1.3`)
- Manual dispatch via GitHub Actions UI

**What it builds**:
- `discovery-server-linux-amd64.tar.gz`
- `discovery-server-linux-arm64.tar.gz`
- `discovery-server-linux-armv7.tar.gz`
- `discovery-client-linux-amd64.tar.gz`
- `discovery-client-linux-arm64.tar.gz`
- `discovery-client-linux-armv7.tar.gz`
- `checksums.txt` - SHA256 checksums for all files

**Usage**:
```bash
# Create and push a tag to trigger release
git tag v1.0.0
git push origin v1.0.0

# Or manually trigger via GitHub UI:
# Go to Actions → Build and Release Binaries → Run workflow
```

### 2. `simple-release.yml` - Single Architecture Release

**Purpose**: Simpler workflow that builds only Linux x86_64 binaries

**Triggers**:
- Push tags matching `v*`
- Manual dispatch via GitHub Actions UI

**What it builds**:
- `discovery-server-linux-amd64.tar.gz`
- `discovery-client-linux-amd64.tar.gz`
- `checksums.txt`

**Usage**:
```bash
# Same as multi-arch workflow
git tag v1.0.0
git push origin v1.0.0
```

## Workflow Features

### ✅ **Automated Features**
- **Cross-compilation** for multiple architectures
- **Static linking** (no runtime dependencies)
- **Version injection** into binaries
- **Checksum generation** for security verification
- **Release notes generation** with installation instructions
- **Artifact uploading** to GitHub Releases
- **Installation testing** (multi-arch workflow only)

### 🔧 **Configuration Options**

Both workflows support these environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `GO_VERSION` | Go version for building | `1.21` |
| `CGO_ENABLED` | Enable/disable CGO | `0` (disabled) |

### 📋 **Manual Dispatch Options**

When running workflows manually, you can specify:

**Multi-Architecture Workflow**:
- `version`: Release version (e.g., `v1.0.0`)
- `architectures`: Comma-separated list (`amd64,arm64,arm`)
- `prerelease`: Mark as pre-release (`true`/`false`)

**Simple Workflow**:
- `version`: Release version (e.g., `v1.0.0`)

## Version Tagging

### **Recommended Version Format**

```bash
# Stable releases
git tag v1.0.0
git tag v1.0.1
git tag v2.0.0

# Pre-releases (marked as pre-release automatically)
git tag v1.0.0-alpha.1
git tag v1.0.0-beta.1
git tag v1.0.0-rc.1
```

### **Version Validation**

- Tags must start with `v` (e.g., `v1.0.0`)
- Semantic versioning is recommended but not enforced
- Pre-release versions containing `alpha`, `beta`, or `rc` are automatically marked as pre-releases

## Build Process

### **Steps Overview**

1. **Checkout** repository code
2. **Setup Go** environment
3. **Determine version** from tag or manual input
4. **Build binaries** for each architecture/component combination
5. **Package** binaries into tar.gz archives
6. **Generate checksums** for verification
7. **Create release** on GitHub with all artifacts
8. **Test installation** (multi-arch workflow only)

### **Build Flags**

All binaries are built with:
```bash
go build -a -installsuffix cgo \
  -ldflags="-w -s -X main.version=$VERSION" \
  -o discovery-$COMPONENT .
```

- `-a`: Force rebuilding of packages
- `-installsuffix cgo`: Add suffix to package install directory
- `-ldflags="-w -s"`: Strip debug info and symbol tables
- `-X main.version=$VERSION`: Inject version into binary

## Release Output

After a successful workflow run, the following will be available:

### **GitHub Release Page**
- Release notes with installation instructions
- Download links for all binary packages
- Checksums file for verification

### **Binary Naming Convention**
```
discovery-{component}-linux-{architecture}.tar.gz

Examples:
- discovery-server-linux-amd64.tar.gz
- discovery-client-linux-arm64.tar.gz
- discovery-server-linux-armv7.tar.gz
```

### **One-Liner Installer Compatibility**
All releases are compatible with the one-liner installer:
```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/YOUR_REPO/main/get.sh | bash
```

## Permissions

Both workflows require the following GitHub permissions:
- `contents: write` - To create releases and upload assets
- `GITHUB_TOKEN` - Automatically provided by GitHub Actions

## Troubleshooting

### **Common Issues**

#### 1. **Build Failures**
```bash
# Check Go modules
cd server && go mod tidy
cd ../client && go mod tidy

# Test local build
make build-all
```

#### 2. **Permission Errors**
- Ensure repository has Actions enabled
- Check if `GITHUB_TOKEN` has write permissions
- Verify branch protection rules allow Actions

#### 3. **Missing Binaries in Release**
- Check workflow logs for build errors
- Verify file paths in upload steps
- Ensure tar.gz files are created successfully

#### 4. **One-Liner Installer Fails**
- Verify release assets are publicly downloadable
- Check binary naming matches expected pattern
- Test manual download URLs

### **Debugging Steps**

1. **Check workflow logs** in GitHub Actions tab
2. **Verify Go module files** are valid
3. **Test local builds** before pushing tags
4. **Validate release assets** after workflow completion

## Local Testing

Before pushing tags, test the build process locally:

```bash
# Test server build
cd server
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o discovery-server .

# Test client build
cd ../client  
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o discovery-client .

# Test binaries
./server/discovery-server --help
./client/discovery-client --help
```

## Customization

### **Adding New Architectures**

To add support for additional architectures, modify the matrix in `release.yml`:

```yaml
strategy:
  matrix:
    arch: [amd64, arm64, arm, 386]  # Add 386 here
    component: [server, client]
```

Then add the architecture mapping in the "Set architecture variables" step.

### **Custom Build Flags**

Modify the build command in the workflow to add custom flags:

```yaml
go build -a -installsuffix cgo \
  -ldflags="-w -s -X main.version=$VERSION -X main.buildDate=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -o discovery-$component .
```

### **Additional Components**

To build additional components, add them to the matrix:

```yaml
strategy:
  matrix:
    arch: [amd64, arm64, arm]
    component: [server, client, admin-tool]  # Add new component here
```

## Security

### **Supply Chain Security**
- All dependencies are pinned to specific versions
- Checksums are generated for all releases
- No external scripts or untrusted code execution

### **Binary Verification**
Users can verify downloads using provided checksums:
```bash
sha256sum -c checksums.txt
```

### **Token Security**
- Uses GitHub-provided `GITHUB_TOKEN`
- No custom tokens or secrets required
- Minimal required permissions