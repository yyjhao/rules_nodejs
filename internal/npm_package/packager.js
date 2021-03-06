/**
 * @license
 * Copyright 2018 The Bazel Authors. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 *
 * You may obtain a copy of the License at
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
const fs = require('fs');
const path = require('path');

function mkdirp(p) {
  if (!fs.existsSync(p)) {
    mkdirp(path.dirname(p));
    fs.mkdirSync(p);
  }
}

function write(p, content, replacements) {
  mkdirp(path.dirname(p));
  replacements.forEach(r => {
    const [regexp, newvalue] = r;
    content = content.replace(regexp, newvalue);
  });
  fs.writeFileSync(p, content);
}

function unquoteArgs(s) {
  return s.replace(/^'(.*)'$/, '$1');
}

function main(args) {
  args = fs.readFileSync(args[0], {encoding: 'utf-8'}).split('\n').map(unquoteArgs);
  const
      [outDir, baseDir, srcsArg, binDir, genDir, depsArg, packagesArg, replacementsArg, packPath,
       publishPath, stampFile] = args;

  const replacements = [
    // Strip content between BEGIN-INTERNAL / END-INTERNAL comments
    [/(#|\/\/)\s+BEGIN-INTERNAL[\w\W]+END-INTERNAL/g, ''],
  ];
  if (stampFile) {
    // The stamp file is expected to look like
    // BUILD_SCM_HASH 83c699db39cfd74526cdf9bebb75aa6f122908bb
    // BUILD_SCM_LOCAL_CHANGES true
    // BUILD_SCM_VERSION 6.0.0-beta.6+12.sha-83c699d.with-local-changes
    // BUILD_TIMESTAMP 1520021990506
    const versionTag = fs.readFileSync(stampFile, {encoding: 'utf-8'})
                           .split('\n')
                           .find(s => s.startsWith('BUILD_SCM_VERSION'));
    // Don't assume BUILD_SCM_VERSION exists
    if (versionTag) {
      const version = versionTag.split(' ')[1].trim();
      replacements.push([/0.0.0-PLACEHOLDER/g, version]);
    }
  }
  const rawReplacements = JSON.parse(replacementsArg);
  for (let key of Object.keys(rawReplacements)) {
    replacements.push([new RegExp(key, 'g'), rawReplacements[key]])
  }

  // src like baseDir/my/path is just copied to outDir/my/path
  for (src of srcsArg.split(',').filter(s => !!s)) {
    const content = fs.readFileSync(src, {encoding: 'utf-8'});
    const outPath = path.join(outDir, path.relative(baseDir, src));
    write(outPath, content, replacements);
  }

  function outPath(f) {
    let rootDir;
    if (!path.relative(binDir, f).startsWith('..')) {
      rootDir = binDir;
    } else if (!path.relative(genDir, f).startsWith('..')) {
      rootDir = genDir;
    } else {
      throw new Error(`dependency ${f} is not under bazel-bin or bazel-genfiles`);
    }
    return path.join(outDir, path.relative(path.join(rootDir, baseDir), f));
  }

  // deps like bazel-bin/baseDir/my/path is copied to outDir/my/path
  for (dep of depsArg.split(',').filter(s => !!s)) {
    const content = fs.readFileSync(dep, {encoding: 'utf-8'});
    write(outPath(dep), content, replacements);
  }

  // package contents like bazel-bin/baseDir/my/directory/* is
  // recursively copied to outDir/my/*
  for (pkg of packagesArg.split(',').filter(s => !!s)) {
    const outDir = outPath(path.dirname(pkg));
    function copyRecursive(base, file) {
      if (fs.lstatSync(path.join(base, file)).isDirectory()) {
        const files = fs.readdirSync(path.join(base, file));
        files.forEach(f => {
          copyRecursive(base, path.join(file, f));
        });
      } else {
        const content = fs.readFileSync(path.join(base, file), {encoding: 'utf-8'});
        write(path.join(outDir, file), content, replacements);
      }
    }
    fs.readdirSync(pkg).forEach(f => {
      copyRecursive(pkg, f);
    });
  }

  const npmTemplate =
      fs.readFileSync(require.resolve('nodejs/run_npm.sh.template'), {encoding: 'utf-8'});
  fs.writeFileSync(packPath, npmTemplate.replace('TMPL_args', `pack ${outDir}`));
  fs.writeFileSync(publishPath, npmTemplate.replace('TMPL_args', `publish ${outDir}`));
}

if (require.main === module) {
  process.exitCode = main(process.argv.slice(2));
}
