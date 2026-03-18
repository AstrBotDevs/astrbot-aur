#!/bin/bash
set -e

# Ensure AUR remote exists
if ! git remote | grep -q "^aur$"; then
    echo "Adding AUR remote..."
    git remote add aur https://aur.archlinux.org/astrbot-git.git
fi

echo "Fetching from AUR..."
git fetch aur

echo "Merging AUR master into local master..."
# Using --allow-unrelated-histories just in case initialization differed
git merge aur/master --allow-unrelated-histories -m "Sync: Merge upstream changes from AUR"

echo "Pushing to GitHub..."
git push origin master

echo "Sync complete!"
