Static builds of the Mosquitto command-line clients (mosquitto_pub, mosquitto_sub and mosquitto_rr), plus a static tcpdump, for linux/amd64, linux/arm64 and linux/arm/v7.

## Building locally

To build mosquitto_sub, mosquitto_pub, mosquitto_rr and tcpdump in dist/ per architecture:

$ docker run --privileged --rm tonistiigi/binfmt --install arm,arm64

$ docker buildx build   --platform linux/amd64,linux/arm64,linux/arm/v7 --output type=local,dest=dist .

To build a different Mosquitto version without editing the Dockerfile, add `--build-arg MOSQUITTO_VERSION=2.1.3`. tcpdump and libpcap versions are set the same way with `TCPDUMP_VERSION` and `LIBPCAP_VERSION`.
For quick iteration, build only `--platform linux/amd64`, which needs no emulation and is much faster.

## Releasing with GitHub Actions

[.github/workflows/release.yml](.github/workflows/release.yml) builds each architecture and publishes a GitHub Release when you push a tag:

$ git tag v2.1.2

$ git push origin v2.1.2

- The tag selects the Mosquitto version: `v2.1.2` builds Mosquitto 2.1.2, whatever the Dockerfile default says.
- To rebuild the same Mosquitto version (for example after bumping Alpine or cJSON), add a build number: `v2.1.2-2`.
- The release gets one tarball per architecture, `mosquitto-clients-<tag>-linux-{amd64,arm64,armv7}.tar.gz`, plus a SHA256SUMS covering the tarballs. Each tarball also contains a SHA256SUMS for the binaries inside it.
- To test a build without releasing, open Actions → release → Run workflow and enter a version. The tarballs are attached to the run as artifacts instead of a release.

## Moving to a new Mosquitto version

Patches live in `patches/<mosquitto-version>/` and are applied in filename order. Only the directory matching the version being built is used, so patches for an old version never get applied to a new one.

1. **Try it unpatched.** Build the new version for amd64 only:

   $ docker buildx build --platform linux/amd64 --build-arg MOSQUITTO_VERSION=2.1.3 --output type=local,dest=dist .

   If it builds and the static check passes, no patches are needed; skip to step 3.

2. **If it fails, carry the old patches forward.** The current patch, `patches/2.1.2/0001-libmosquitto_static-include-dirs.patch`, fixes the static library missing include directories (errors like `property_common.h: No such file or directory` or `utlist.h: No such file or directory`). See whether it still applies:

   $ curl -fsSLO https://mosquitto.org/files/source/mosquitto-2.1.3.tar.gz && tar xzf mosquitto-2.1.3.tar.gz

   $ patch -d mosquitto-2.1.3 -p1 --forward --dry-run < patches/2.1.2/0001-libmosquitto_static-include-dirs.patch

   - Applies cleanly: copy it to `patches/2.1.3/`.
   - "Reversed (or previously applied) patch detected": upstream fixed it, so don't copy it.
   - Hunks fail: the file changed upstream. Make a fresh patch (below).

   To make a fresh patch, unpack the source twice, edit only the `b` copy until the build works, then diff:

   $ mkdir a b && tar xzf mosquitto-2.1.3.tar.gz -C a --strip-components=1 && tar xzf mosquitto-2.1.3.tar.gz -C b --strip-components=1

   $ (edit files under b/)

   $ mkdir -p patches/2.1.3 && diff -ruN a b > patches/2.1.3/0001-short-description.patch

   Put a sentence or two at the top of the patch file (above the first `---` line) explaining what it fixes; `patch` ignores that text. Rebuild with the command from step 1 to confirm.

3. **Update the default.** Set `ARG MOSQUITTO_VERSION` in the Dockerfile to the new version so plain local builds use it.

4. **Release.** Commit, then tag and push `v2.1.3` as above.

The other versions in the Dockerfile (`ALPINE_VERSION`, `CJSON_VERSION`, `TCPDUMP_VERSION`, `LIBPCAP_VERSION`) can be bumped the same way. Use a `-N` tag suffix to release a rebuild of an existing Mosquitto version.

## License

The files in this repository (the Dockerfile, workflow and patches) are released under the MIT license; see [LICENSE](LICENSE).

The built binaries are not covered by that license. The mosquitto_* binaries are Eclipse Mosquitto, dual-licensed under the [Eclipse Public License 2.0](https://www.eclipse.org/legal/epl-2.0/) and the [Eclipse Distribution License 1.0](https://www.eclipse.org/org/documents/edl-v10.php), and are statically linked with OpenSSL (Apache License 2.0), cJSON (MIT) and musl libc (MIT). tcpdump is released under the 3-clause BSD license and is statically linked with libpcap (BSD) and musl libc (MIT); it is built without OpenSSL, so ESP decryption (`-E`) is not available. Anyone redistributing the binaries must follow those licenses. Their license texts are included in each build under `licenses/`.
