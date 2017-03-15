package lix.client;

import haxe.crypto.Md5;

using haxe.io.Path;
using sys.FileSystem;
using sys.io.File;
using haxe.Json;

enum ArchiveKind {
  Zip;
  Tar;
}

typedef ArchiveJob = {
  var normalized(default, null):Url;
  var url(default, null):Url;
  var lib(default, null):LibVersion;
  @:optional var kind(default, null):Null<ArchiveKind>;
}

@:structInit class ArchiveInfos {
  public var name(default, null):String;
  public var version(default, null):String;
  public var classPath(default, null):String;
}

class DownloadedArchive {
  
  /**
   * The url this archive was downloaded from
   */
  public var source(default, null):Url;
  /**
   * The (initially temporary) location this archive was downloaded to
   */
  public var location(default, null):String;
  /**
   * The root directory of this archive, relative to `location`
   */
  public var relRoot(default, null):String;
  /**
   * The absolute path to the root of the downloaded archive
   */
  public var absRoot(get, never):String;
    inline function get_absRoot()
      return '$location/$relRoot'.removeTrailingSlashes();
     
  public var infos(default, null):ArchiveInfos;
  
  public function new(source, location) {
    this.source = source;
    this.location = location;
    this.relRoot = seekRoot(location);
    
    this.infos = readInfos(absRoot);
  }
  
  static function seekRoot(path:String) 
    return switch path.readDirectory() {
      case [v] if ('$path/$v'.isDirectory()):
        '$v/' + seekRoot('$path/$v');
      default:
        '';
    }
    
  public function saveAs(storageRoot:String, implicit:LibVersion, ?explicit:LibVersion):Promise<DownloadedArchive> {
    
    var found:LibVersion = {
      name: Some(infos.name),
      versionNumber: Some(infos.version.urlEncode()),
      versionId: None,
    }

    var final = implicit.merge(found).merge(explicit);

    var name = switch final.name {
      case None:
        return new Error('unable to determine library name of $source');
      case Some(v):
        v;
    }
    
    var versionNumber = switch final.versionNumber {
      case None: throw "unreachable";//unless proven otherwise
      case Some(v): v;
    }
        
    var versionId = switch final.versionId {
      case None: 'http/'+ Md5.encode(source);
      case Some(v): v;
    }
    
    this.infos = {
      name: name,
      version: versionNumber,
      classPath: infos.classPath,
    }
    
    var path = '$name/$versionNumber/$versionId';
    
    var target = '$storageRoot/$path';
    
    var archive = null;
    if (target.exists())
      target.rename(archive = '$target-archived@${Date.now().getTime()}');
      
    Fs.ensureDir(target);  
    absRoot.rename(target);
    
    if (archive != null)
      Fs.delete(archive);

    location = storageRoot;
    relRoot = path;
    
    this.savedAs = Some(({
      name: Some(name),
      versionNumber: Some(versionNumber),
      versionId: Some(versionId),
    }:LibVersion));
    
    return this;
  }
  
  function readInfos(root:String):ArchiveInfos {
    
    var files = root.readDirectory();
    
    function guessClassPath() 
      return 
        if (files.indexOf('src') != -1) 'src';
        else if (files.indexOf('hx') != -1) 'hx';
        else '';
        
    return 
      if (files.indexOf('haxelib.json') != -1) {
        //TODO: there's a lot of errors to be caught here
        var info:{ name: String, version:String, ?classPath:String } = '$root/haxelib.json'.getContent().parse();
        {
          name: info.name,
          version: info.version,
          classPath: switch info.classPath {
            case null: '';
            case v: v;
          },
        }
      }
      else if (files.indexOf('package.json') != -1) {
        var info:{ name: String, version:String, } = '$root/package.json'.getContent().parse();
        {
          name: info.name,
          version: info.version,
          classPath: guessClassPath(),
        }
      }
      else {        
        {
          name: null,
          version: '0.0.0',
          classPath: guessClassPath(),
        }
      }
  }    
}