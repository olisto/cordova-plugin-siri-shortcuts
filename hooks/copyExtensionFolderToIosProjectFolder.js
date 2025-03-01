// @ts-check

var fs = require('fs');
var path = require('path');
var Q = require('q');

function log(logString, type) {
  var prefix;
  var postfix = '';
  switch (type) {
    case 'error':
      prefix = '\x1b[1m' + '\x1b[31m' + '💥 😨 '; // bold, red
      throw new Error(prefix + logString + 'x1b[0m'); // reset
    case 'info':
      prefix =
          '\x1b[40m' +
          '\x1b[37m' +
          '\x1b[2m' +
          '☝️ Siri [INFO] ' +
          '\x1b[0m\x1b[40m' +
          '\x1b[33m'; // fgWhite, dim, reset, bgBlack, fgYellow
      break;
    case 'start':
      prefix = '\x1b[40m' + '\x1b[36m'; // bgBlack, fgCyan
      break;
    case 'success':
      prefix = '\x1b[40m' + '\x1b[32m' + '✔ '; // bgBlack, fgGreen
      postfix = ' 🦄  🎉  🤘';
      break;
  }

  console.log(prefix + logString + postfix);
}

function getPreferenceValue (config, name) {
  var value = config.match(new RegExp('name="' + name + '" value="(.*?)"', "i"));
  if(value && value[1]) {
    return value[1];
  } else {
    return null;
  }
}

console.log('\x1b[40m');
log(
    'Running copyExtensionFolderToIosProject hook, copying extension folder ...',
    'start'
);

// http://stackoverflow.com/a/26038979/5930772
var copyFileSync = function(source, target, prefix) {
  var targetFile = target;

  // If target is a directory a new file with the same name will be created
  if (fs.existsSync(target)) {
    if (fs.lstatSync(target).isDirectory()) {
      targetFile = path.join(target, path.basename(source));
    }
  }

  var dest = prefix ? path.join(path.dirname(targetFile), prefix + '-' + path.basename(targetFile)) : targetFile;
  fs.writeFileSync(dest, fs.readFileSync(source));
};
var copyFolderRecursiveSync = function(source, target) {
  var files = [];

  // Check if folder needs to be created or integrated
  var targetFolder = path.join(target, path.basename(source));
  if (!fs.existsSync(targetFolder)) {
    fs.mkdirSync(targetFolder);
  }

  // Copy
  if (fs.lstatSync(source).isDirectory()) {
    files = fs.readdirSync(source);
    files.forEach(function(file) {
      var curSource = path.join(source, file);
      if (fs.lstatSync(curSource).isDirectory()) {
        copyFolderRecursiveSync(curSource, targetFolder);
      } else {
        copyFileSync(curSource, targetFolder);
      }
    });
  }
};

function getCordovaParameter(variableName, contents) {
  var variable;
  if(process.argv.join("|").indexOf(variableName + "=") > -1) {
    var re = new RegExp(variableName + '=(.*?)(\||$))', 'g');
    variable = process.argv.join("|").match(re)[1];
  } else {
    variable = getPreferenceValue(contents, variableName);
  }
  return variable;
}

module.exports = function(context) {
  var deferral = new Q.defer();

  var contents = fs.readFileSync(
      path.join(context.opts.projectRoot, 'config.xml'),
      'utf-8'
  );

  var iosFolder = context.opts.cordova.project
      ? context.opts.cordova.project.root
      : path.join(context.opts.projectRoot, 'platforms/ios/');
  fs.readdir(iosFolder, function(err, data) {
    var projectFolder;
    var projectName;
    var srcFolder;
    // Find the project folder by looking for *.xcodeproj
    if (data && data.length) {
      data.forEach(function(folder) {
        if (folder.match(/\.xcodeproj$/)) {
          projectFolder = path.join(iosFolder, folder);
          projectName = path.basename(folder, '.xcodeproj');
        }
      });
    }

    if (!projectFolder || !projectName) {
      log('Could not find an .xcodeproj folder in: ' + iosFolder, 'error');
    }

    // Get the widget name and location from the parameters or the config file
    var EXTENSION_PATH = getCordovaParameter("SIRI_EXTENSION_PATH", contents);
    var DEPENDENCIES = getCordovaParameter("SIRI_DEPENDENCIES", contents);

    var dependencies = DEPENDENCIES ? DEPENDENCIES.split(',') : [];
    var extensionName = "SiriIntents";

    if (EXTENSION_PATH) {
      srcFolder = path.join(
          context.opts.projectRoot,
          EXTENSION_PATH,
          extensionName + '/'
      );
    } else {
      srcFolder = path.join(
          context.opts.projectRoot,
          'www',
          extensionName + '/'
      );
    }
    if (!fs.existsSync(srcFolder)) {
      log(
          'Missing extension folder in ' + srcFolder + '. Should have the same name as your extension: ' + extensionName,
          'error'
      );
    }

    // Copy widget folder
    copyFolderRecursiveSync(
        srcFolder,
        path.join(context.opts.projectRoot, 'platforms', 'ios')
    );

    log('Successfully copied extension folder!', 'success');

    if(DEPENDENCIES) {
      dependencies.forEach(file => {
        var srcFile = path.join(
            iosFolder,
            projectName,
            file.trim()
        );

        var destFolder = path.join(iosFolder, extensionName);

        copyFileSync(srcFile, destFolder, extensionName);
      })
    }

    log('Successfully copied dependency files!', 'success');
    console.log('\x1b[0m'); // reset

    deferral.resolve();
  });

  return deferral.promise;
};
