#!/usr/bin/env bash

REMOTE="git@github.com:blaenk/blaenk.github.io.git"
SITE="generated/preview/"
DEPLOY="deploy/"

info() {
  printf "  [ \033[00;34m..\033[0m ] $1\n"
}

success() {
  printf "  [ \033[00;32mOK\033[0m ] $1\n"
}

fail() {
  printf "  [ \033[0;31mFAIL\033[0m ] $1\n"
  exit
}

# shouldn't happen since `site` binary is usually at root to
# begin with, but doesn't hurt to check
dir_check() {
  if [ ! -f "Setup.hs" ]; then
    fail "not at root dir"
  fi
}

git_check() {
  git rev-parse || fail "$PWD is already under git control"
}

setup() {
  dir_check

  rm -rf $DEPLOY
  mkdir $DEPLOY

  info "created $DEPLOY"
  cd $DEPLOY
  git_check

  git init -q
  info "initialized git"
  git checkout --orphan master -q
  info "established master branch"
  git remote add origin $REMOTE
  info "established git remote"

  success "setup complete"
}

deploy() {
  dir_check

  COMMIT="`git log -1 HEAD --pretty=format:%H`"
  SHA=${COMMIT:0:8}

  info "commencing deploy operation based off of $SHA"

  # clean out _deploy and move in the new files
  rm -rf "$DEPLOY/*"
  info "cleaned out $DEPLOY"

  cp -r "$SITE"/* $DEPLOY
  info "copied $SITE into $DEPLOY"

  cd $DEPLOY

  git add .
  info "added files to git"

  git commit -m "generated from $SHA" -q
  info "committed site"

  git push origin master --force -q
  success "deployed site"
}

case "$1" in
  setup )
    setup;;
  deploy )
    deploy;;
  * )
    fail "invalid operation";;
  esac

