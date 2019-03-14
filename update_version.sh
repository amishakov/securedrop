#!/bin/bash
## Usage: ./update_version.sh <version>

set -e

# Only run this on the development environment, where dch is available
if ! which dch > /dev/null ; then
  echo 'dch is missing'
  echo 'run with securedrop/bin/dev-shell ../update_version.sh <version>'
  exit 1
fi

cd "$(git rev-parse --show-toplevel)"

# Since we may be running in a container, we may not  have access to ~/.gitconfig. So the
# repo-level git user config file must be set.
if ! grep -q '^\[user\]' .git/config; then
    echo 'Please set your git user config in .git/config and retry!'
    exit 1
fi

readonly NEW_VERSION=$1

export EDITOR=vim

if [ -z "$NEW_VERSION" ]; then
  echo "You must specify the new version!"
  exit 1
fi

if [[ $NEW_VERSION == *-rc* ]]; then
  echo "Release candidates should use the versioning 0.x.y~rcZ!"
  exit 1
fi

# Get the old version from securedrop/version.py
old_version_regex="^__version__ = '(.*)'$"
[[ "$(cat securedrop/version.py)" =~ $old_version_regex ]]
OLD_VERSION=${BASH_REMATCH[1]}

# Update the version shown to users of the web application.
sed -i "s@$(echo "${OLD_VERSION}" | sed 's/\./\\./g')@$NEW_VERSION@g" securedrop/version.py

# Update the version in the Debian packages
sed -i "s/^\(Version: \).*/\1$NEW_VERSION/" install_files/securedrop-app-code/debian/control
sed -i "s/^\(Version: [0-9.]\++\).*/\1$NEW_VERSION/" install_files/securedrop-ossec-agent/DEBIAN/control
sed -i "s/^\(Version: [0-9.]\++\).*/\1$NEW_VERSION/" install_files/securedrop-ossec-server/DEBIAN/control
sed -i "s/^\(Version: [0-9.]\++\).*/\1$NEW_VERSION/" install_files/securedrop-keyring/DEBIAN/control
sed -i "s/^\(Version: [0-9.]\++\).*/\1$NEW_VERSION/" install_files/securedrop-config/DEBIAN/control

# Update the version used by Ansible for the filename of the output of the deb building role
sed -i "s/^\(securedrop_app_code_version: \"\).*/\1$NEW_VERSION\"/" install_files/ansible-base/group_vars/all/securedrop

# Update the version in molecule testinfra vars
sed -i "s@$(echo "${OLD_VERSION}" | sed 's/\./\\./g')@$NEW_VERSION@g" molecule/builder-trusty/tests/vars.yml

# Update the version that we tell people to check out in the install doc
sed -i "s@$(echo "${OLD_VERSION}" | sed 's/\./\\./g')@$NEW_VERSION@g" docs/set_up_admin_tails.rst
sed -i "s@$(echo "${OLD_VERSION}" | sed 's/\./\\./g')@$NEW_VERSION@g" docs/conf.py

# If version doesnt have an rc designator, its considered stable
# theres a few things that peg to that stable version like upgrade testing logic
if [[ ! $NEW_VERSION == *~rc* ]]; then
    echo "${NEW_VERSION}" > molecule/shared/stable.ver
fi

# Update the changelog
sed -i "s/\(## ${OLD_VERSION}\)/## ${NEW_VERSION}\n\n\n\n\1/g" changelog.md
"$EDITOR" +5 changelog.md

export DEBEMAIL="${DEBEMAIL:-securedrop@freedom.press}"
export DEBFULLNAME="${DEBFULLNAME:-SecureDrop Team}"

# Update the changelog in the Debian package
dch -b -v "${NEW_VERSION}+trusty" -D trusty -c install_files/ansible-base/roles/build-securedrop-app-code-deb-pkg/files/changelog-trusty
dch -b -v "${NEW_VERSION}+xenial" -D xenial -c install_files/ansible-base/roles/build-securedrop-app-code-deb-pkg/files/changelog-xenial
# Commit the change
# Due to `set -e`, providing an empty commit message here will cause the script to abort early.
git commit -a

echo "[ok] Version update complete and committed."

# We use the version string 0.x.y~rcz for the release candidate deb packages but
# we use 0.x.y-rcz for the tags as "~" is an invalid character in a git tag.
if [[ $NEW_VERSION == *~* ]]; then
  # This is an rc and we should replace "~" with "-" in the tag version.
  TAG_VERSION="${NEW_VERSION//\~/\-}"
else
  # This is a stable release.
  TAG_VERSION="${NEW_VERSION}"
fi

git tag -a "${TAG_VERSION}"
TAGFILE="${TAG_VERSION}.tag"
git cat-file tag "${TAG_VERSION}" > "${TAGFILE}"
echo "A tag has been generated: ${TAGFILE}"

# Remind the developer that in order to create a signed tag for release, they must proceed with the airgapped signing process.
echo "If you wish to release this version, please continue the airgapped signing process with the tag file."
