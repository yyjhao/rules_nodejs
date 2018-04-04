# Copyright 2017 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Install NodeJS

This is a repository rule, see https://docs.bazel.build/versions/master/skylark/repository_rules.html

This runs when the user invokes node_repositories() from their WORKSPACE.
"""

load(":node_labels.bzl", "get_node_label")
load("//internal/common:check_bazel_version.bzl", "check_bazel_version")
load("//internal/npm_install:npm_install.bzl", "yarn_install")

def _node_impl(repository_ctx):
  os_name = repository_ctx.os.name.lower()
  if os_name.startswith("mac os"):
    repository_ctx.download_and_extract(
        [
            "https://mirror.bazel.build/nodejs.org/dist/v8.9.1/node-v8.9.1-darwin-x64.tar.gz",
            "https://nodejs.org/dist/v8.9.1/node-v8.9.1-darwin-x64.tar.gz",
        ],
        stripPrefix = "node-v8.9.1-darwin-x64",
        sha256 = "05c992a6621d28d564b92bf3051a5dc0adf83839237c0d4653a8cdb8a1c73b94"
    )
  elif os_name.find("windows") != -1:
    repository_ctx.download_and_extract(
        [
            "https://mirror.bazel.build/nodejs.org/dist/v8.9.1/node-v8.9.1-win-x64.zip",
            "http://nodejs.org/dist/v8.9.1/node-v8.9.1-win-x64.zip",
        ],
        stripPrefix = "node-v8.9.1-win-x64",
        sha256 = "db89c6e041da359561fbe7da075bb4f9881a0f7d3e98c203e83732cfb283fa4a"
    )
  else:
    repository_ctx.download_and_extract(
        [
            "http://nodejs.org/dist/v8.9.1/node-v8.9.1-linux-arm64.tar.xz",
        ],
        stripPrefix = "node-v8.9.1-linux-arm64",
        sha256 = "f774660980dcf931bf29847a5f26317823a063fa4a56f85f37c3222d77cce7c1"
    )
  if os_name.lower().find("windows") != -1:
    # The windows distribution of nodejs has the binaries in different paths
    node = "node.exe"
    npm = "node_modules/npm/bin/npm-cli.js"
  else:
    node = "bin/node"
    npm = "bin/npm"
  repository_ctx.file("BUILD.bazel", content="""#Generated by node_repositories.bzl
package(default_visibility = ["//visibility:public"])
exports_files(["{0}", "run_npm.sh.template"])
alias(name = "node", actual = "{0}")
sh_binary(
  name = "npm",
  srcs = ["npm.sh"],
)
""".format(node))

  # `yarn publish` is not ready for use under Bazel, see https://github.com/yarnpkg/yarn/issues/610
  repository_ctx.file("run_npm.sh.template", content="""
NODE="{}"
NPM="{}"
"$NODE" "$NPM" TMPL_args "$@"
""".format(repository_ctx.path(node), repository_ctx.path(npm)))

  repository_ctx.file("npm.sh", content="""#!/bin/bash
#Generated by node_repositories.bzl
""" + "".join(["""
ROOT="{}"
NODE="{}"
SCRIPT="{}"
(cd "$ROOT"; "$NODE" "$SCRIPT" --scripts-prepend-node-path=true "$@")
""".format(
    repository_ctx.path(package_json).dirname,
    repository_ctx.path(node),
    repository_ctx.path(npm))
    for package_json in repository_ctx.attr.package_json]), executable = True)

_node_repo = repository_rule(
    _node_impl,
    attrs = { "package_json": attr.label_list() },
)

# def _write_node_modules_impl(repository_ctx):
  # WORKAROUND for https://github.com/bazelbuild/bazel/issues/374#issuecomment-296217940
  # Bazel does not allow labels to start with `@`, so when installing eg. the `@types/node`
  # module from the @types scoped package, you'll get an error.
  # The workaround is to move the rule up one level, from /node_modules to the project root.
  # For now, users must instead write their own /BUILD file on setup.

  # repository_ctx.symlink(project_dir.get_child("node_modules"), "node_modules")
  # add a BUILD file inside the user's node_modules project folder
  # repository_ctx.file("installed/BUILD", """
  #   filegroup(name = "node_modules", srcs = glob(["node_modules/**/*"]), visibility = ["//visibility:public"])
  # """)

# _write_node_modules = repository_rule(
#     _write_node_modules_impl,
#     attrs = { "package_json": attr.label() },
# )

def _yarn_impl(repository_ctx):
  # Yarn is a package manager that downloads dependencies. Yarn is an improvement over the `npm` tool in
  # speed and correctness. We download a specific version of Yarn to ensure a hermetic build.
  repository_ctx.file("BUILD.bazel", content="""#Generated by node_repositories.bzl
package(default_visibility = ["//visibility:public"])
sh_binary(
  name = "yarn",
  srcs = ["yarn.sh"],
)
""")
  node = get_node_label(repository_ctx)

  # Using process.env['PATH'] here to add node to the environment PATH on Windows
  # before running bin/yarn.js. export PATH="$NODE_PATH":$PATH in yarn.sh below
  # has no any effect on Windows and setting process.env['PATH'] has no effect
  # on OSX
  # TODO: revisit setting node environment PATH when bash dependency is eliminated
  repository_ctx.file("yarn.js", content="""//Generated by node_repositories.bzl
const {{spawnSync}} = require('child_process');
const node = "{}";
const nodePath = "{}";
const yarn = "{}";
process.env['PATH'] = `"${{nodePath}}":${{process.env['PATH']}}`;
spawnSync(node, [yarn, ...process.argv.slice(2)], {{stdio: ['ignore', process.stdout, process.stderr]}});
""".format(
    repository_ctx.path(node),
    repository_ctx.path(node).dirname,
    repository_ctx.path("bin/yarn.js")))

  repository_ctx.file("yarn.sh", content="""#!/bin/bash
#Generated by node_repositories.bzl
""" + "".join(["""
NODE="{}"
NODE_PATH="{}"
SCRIPT="{}"
ROOT="{}"
export PATH="$NODE_PATH":$PATH
"$NODE" "$SCRIPT" --cwd "$ROOT" "$@"
""".format(
    repository_ctx.path(node),
    repository_ctx.path(node).dirname,
    repository_ctx.path("yarn.js"),
    repository_ctx.path(package_json).dirname)
    for package_json in repository_ctx.attr.package_json]), executable = True)
  repository_ctx.download_and_extract(
      [
          "https://mirror.bazel.build/github.com/yarnpkg/yarn/releases/download/v1.3.2/yarn-v1.3.2.tar.gz",
          "https://github.com/yarnpkg/yarn/releases/download/v1.3.2/yarn-v1.3.2.tar.gz",
      ],
      stripPrefix = "yarn-v1.3.2",
      sha256 = "6cfe82e530ef0837212f13e45c1565ba53f5199eec2527b85ecbcd88bf26821d"
  )

_yarn_repo = repository_rule(
    _yarn_impl,
    attrs = { "package_json": attr.label_list() },
)

def node_repositories(package_json):
  """To be run in user's WORKSPACE to install rules_nodejs dependencies.

  When the rule executes, it downloads node, npm, and yarn.
  We fetch a specific version of Node, to ensure builds are hermetic, and to allow developers to skip installation of node if the entire toolchain is built on Bazel.

  It exposes workspaces `@nodejs` and `@yarn` containing some rules the user can call later:

  - Run node: `bazel run @nodejs//:node path/to/program.js`
  - Install dependencies using npm: `bazel run @nodejs//:npm install`
  - Install dependencies using yarn: `bazel run @yarn//:yarn`

  Note that the dependency installation scripts will run in each subpackage indicated by the `package_json` attribute.

  This approach uses npm/yarn as the package manager. You could instead have Bazel act as the package manager, running the install behind the scenes.
  See the `npm_install` and `yarn_install` rules, and the discussion in the README.

  Example:

  ```
  load("@build_bazel_rules_nodejs//:defs.bzl", "node_repositories")
  node_repositories(package_json = ["//:package.json", "//subpkg:package.json"])
  ```

  Running `bazel run @yarn//:yarn` in this repo would create `/node_modules` and `/subpkg/node_modules`.

  Args:
    package_json: a list of labels, which indicate the package.json files that need to be installed.
  """
  # Windows users need sh_binary wrapped as an .exe
  check_bazel_version("0.5.4")

  _node_repo(name = "nodejs", package_json = package_json)

  _yarn_repo(name = "yarn", package_json = package_json)

  yarn_install(
      name = "build_bazel_rules_nodejs_npm_install_deps",
      package_json = "@build_bazel_rules_nodejs//internal/npm_install:package.json",
      yarn_lock = "@build_bazel_rules_nodejs//internal/npm_install:yarn.lock",
  )

  yarn_install(
      name = "build_bazel_rules_nodejs_rollup_deps",
      package_json = "@build_bazel_rules_nodejs//internal/rollup:package.json",
      yarn_lock = "@build_bazel_rules_nodejs//internal/rollup:yarn.lock",
  )
