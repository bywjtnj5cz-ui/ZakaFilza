#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MoyuTool Xcode 工程生成器
用法: python3 Scripts/gen_xcodeproj.py
会自动扫描源码目录，生成/重建 MoyuTool.xcodeproj
"""
import os
import uuid
import plistlib
from pathlib import Path

# 工程根目录
ROOT = Path(__file__).resolve().parent.parent
PROJECT_NAME = "MoyuTool"
BUNDLE_ID = "com.iosmytool"
APP_DISPLAY_NAME = "墨鱼Tool"
IOS_DEPLOYMENT_TARGET = "16.0"

# 生成唯一 ID（24位十六进制）
def gen_id():
    return uuid.uuid4().hex[:24].upper()

def collect_files(directory, extensions):
    """收集目录下指定扩展名的文件"""
    files = []
    for root, dirs, filenames in os.walk(directory):
        # 跳过隐藏目录
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        for f in filenames:
            if f.endswith(extensions) and not f.startswith('.'):
                files.append(os.path.join(root, f))
    return sorted(files)

def write_file(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

def swift_escape(s):
    """把文本安全转义成 Swift 单行字符串字面量内容"""
    out = []
    for ch in s:
        if ch == '\\':
            out.append('\\\\')
        elif ch == '"':
            out.append('\\"')
        elif ch == '\n':
            out.append('\\n')
        elif ch == '\r':
            out.append('\\r')
        elif ch == '\t':
            out.append('\\t')
        else:
            out.append(ch)
    return ''.join(out)

def generate_embedded_resources():
    """把 Resources 下的 html/json 转成 Swift 字符串常量编译进二进制, IPA 中不再携带明文文件"""
    html_path = ROOT / PROJECT_NAME / "Resources" / "file_manager.html"
    json_path = ROOT / PROJECT_NAME / "Resources" / "default_config.json"
    html = html_path.read_text(encoding='utf-8') if html_path.exists() else ''
    cfg = json_path.read_text(encoding='utf-8') if json_path.exists() else '{}'
    code = (
        "//\n"
        "//  GeneratedResources.swift\n"
        "//  自动生成 — 由 Scripts/gen_xcodeproj.py 从 Resources 内嵌, 请勿手改\n"
        "//  目的: IPA 包内不携带 .html/.json 明文文件 (防提取二改)\n"
        "//\n\n"
        "enum BundledResources {\n"
        f"    static let fileManagerHTML = \"{swift_escape(html)}\"\n"
        f"    static let defaultConfigJSON = \"{swift_escape(cfg)}\"\n"
        "}\n"
    )
    write_file(ROOT / PROJECT_NAME / "GeneratedResources.swift", code)
    print(f"    已内嵌: file_manager.html ({len(html)} 字节), default_config.json ({len(cfg)} 字节)")

def generate_scheme(target_id):
    """生成共享 scheme, 供 xcodebuild -scheme MoyuTool / GitHub Actions 使用
    BlueprintIdentifier 必须与 pbxproj 中的 target_id 一致, 故在生成工程时同步写入"""
    scheme_dir = ROOT / f"{PROJECT_NAME}.xcodeproj" / "xcshareddata" / "xcschemes"
    scheme_path = scheme_dir / f"{PROJECT_NAME}.xcscheme"
    content = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target_id}"
               BuildableName = "{PROJECT_NAME}.app"
               BlueprintName = "{PROJECT_NAME}"
               ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target_id}"
            BuildableName = "{PROJECT_NAME}.app"
            BlueprintName = "{PROJECT_NAME}"
            ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target_id}"
            BuildableName = "{PROJECT_NAME}.app"
            BlueprintName = "{PROJECT_NAME}"
            ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''
    write_file(scheme_path, content)
    return scheme_path

def main():
    print(f"[*] 生成 {PROJECT_NAME}.xcodeproj ...")

    # 收集源码文件
    swift_sources = []
    swift_sources += collect_files(ROOT / PROJECT_NAME, '.swift')
    swift_sources += collect_files(ROOT / "Exploits", '.swift')

    # 收集 ObjC 源码（.m 编译，.h 仅引用）
    objc_m_files = collect_files(ROOT / "Exploits", '.m')
    objc_h_files = collect_files(ROOT / "Exploits", '.h')
    # 收集 C 源码（FilzaJailedDS 的 kexploit/XPF/ChOma 等）
    c_files = collect_files(ROOT / "Exploits", '.c')

    # Bridging header
    bridging_header = ROOT / PROJECT_NAME / f"{PROJECT_NAME}-Bridging-Header.h"

    # 资源文件不再打进 IPA: .html/.json 全部编译进二进制 (防提取)
    # 由 generate_embedded_resources() 生成 GeneratedResources.swift, 此处资源列表留空
    resources = []

    # 生成内嵌资源 Swift 文件 (file_manager.html / default_config.json → 字符串常量)
    generate_embedded_resources()

    print(f"    Swift 源码: {len(swift_sources)} 个")
    print(f"    ObjC .m: {len(objc_m_files)} 个, .h: {len(objc_h_files)} 个")
    print(f"    C 源码: {len(c_files)} 个")
    print(f"    资源文件: {len(resources)} 个 (HTML/JSON 已内嵌进二进制)")

    # 生成 pbxproj 内容 (返回 target_id 供 scheme 使用)
    pbxproj, target_id = generate_pbxproj(swift_sources, objc_m_files, objc_h_files,
                                          c_files, bridging_header, resources)

    # 写入 xcodeproj
    proj_dir = ROOT / f"{PROJECT_NAME}.xcodeproj"
    proj_dir.mkdir(exist_ok=True)
    write_file(proj_dir / "project.pbxproj", pbxproj)

    # 生成共享 scheme (xcodebuild -scheme MoyuTool 依赖它)
    scheme_path = generate_scheme(target_id)

    print(f"[✓] 工程已生成: {proj_dir}")
    print(f"[✓] 共享 scheme 已生成: {scheme_path}")

def generate_pbxproj(swift_sources, objc_m_files, objc_h_files, c_files, bridging_header, resources):
    # 所有源文件（swift + .m + .c 都要编译）
    all_compile_sources = swift_sources + objc_m_files + c_files

    # 按目录分组源码
    main_sources = [s for s in swift_sources if 'Exploits' not in s]
    exploit_dirs = {}
    for s in swift_sources:
        if 'Exploits' in s:
            rel = os.path.relpath(s, ROOT / "Exploits")
            subdir = rel.split(os.sep)[0]
            exploit_dirs.setdefault(subdir, []).append(s)
    # 把 .m、.h、.c 也归入对应子目录
    for f in objc_m_files + objc_h_files + c_files:
        rel = os.path.relpath(f, ROOT / "Exploits")
        subdir = rel.split(os.sep)[0]
        exploit_dirs.setdefault(subdir, []).append(f)

    # 递归收集 Exploits 下所有子目录，用于 HEADER_SEARCH_PATHS
    header_dirs = []
    for root, dirs, files in os.walk(ROOT / "Exploits"):
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        rel = os.path.relpath(root, ROOT)
        header_dirs.append(f"$(SRCROOT)/{rel}")

    # 各个 section 的 ID
    proj_id = gen_id()
    target_id = gen_id()
    main_group_id = gen_id()
    sources_group_id = gen_id()
    resources_group_id = gen_id()
    exploits_group_id = gen_id()
    products_group_id = gen_id()
    # 为每个 exploit 子目录生成 group ID
    exploit_subgroup_ids = {name: gen_id() for name in exploit_dirs}
    build_phase_sources_id = gen_id()
    build_phase_resources_id = gen_id()
    build_phase_frameworks_id = gen_id()
    config_list_proj_id = gen_id()
    config_list_target_id = gen_id()
    config_debug_proj_id = gen_id()
    config_release_proj_id = gen_id()
    config_debug_target_id = gen_id()
    config_release_target_id = gen_id()
    product_ref_id = gen_id()

    lines = []
    lines.append("// !$*UTF8*$!")
    lines.append("{")
    lines.append("\tarchiveVersion = 1;")
    lines.append("\tclasses = {")
    lines.append("\t};")
    lines.append("\tobjectVersion = 56;")
    lines.append("\tobjects = {")
    lines.append("")

    # 先生成所有 PBXFileReference 的 ID（每个文件一个唯一 ID）
    file_refs = {}
    for src in swift_sources + objc_m_files + c_files + objc_h_files + resources:
        file_refs[src] = gen_id()
    bridge_id = gen_id()
    file_refs['BridgingHeader'] = bridge_id
    assets_id = gen_id()
    file_refs['Assets'] = assets_id
    info_plist_id = gen_id()
    file_refs['Info.plist'] = info_plist_id

    # PBXBuildFile section —— PBXBuildFile 和 PBXFileReference 必须用不同 ID
    lines.append("/* Begin PBXBuildFile section */")
    build_files = {}
    for src in swift_sources:
        bid = gen_id()
        build_files[src] = bid
        lines.append(f"\t\t{bid} /* {os.path.basename(src)} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[src]} /* {os.path.basename(src)} */; }};")
    for m in objc_m_files:
        bid = gen_id()
        build_files[m] = bid
        lines.append(f"\t\t{bid} /* {os.path.basename(m)} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[m]} /* {os.path.basename(m)} */; }};")
    for c in c_files:
        bid = gen_id()
        build_files[c] = bid
        lines.append(f"\t\t{bid} /* {os.path.basename(c)} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[c]} /* {os.path.basename(c)} */; }};")
    for res in resources:
        bid = gen_id()
        build_files[res] = bid
        lines.append(f"\t\t{bid} /* {os.path.basename(res)} in Resources */ = {{isa = PBXBuildFile; fileRef = {file_refs[res]} /* {os.path.basename(res)} */; }};")
    # Assets.xcassets
    assets_build_id = gen_id()
    build_files['Assets'] = assets_build_id
    lines.append(f"\t\t{assets_build_id} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {assets_id} /* Assets.xcassets */; }};")
    lines.append("/* End PBXBuildFile section */")
    lines.append("")

    # PBXFileReference section
    lines.append("/* Begin PBXFileReference section */")
    def ref_path(filepath):
        """计算文件相对于其所在 group 的路径"""
        if 'Exploits' in filepath:
            # Exploits 下的文件，相对于 Exploits/<subdir>/ 的路径
            rel = os.path.relpath(filepath, ROOT / "Exploits")
            parts = rel.split(os.sep)
            if len(parts) > 1:
                return os.path.join(*parts[1:])
            return parts[0]
        else:
            return os.path.basename(filepath)

    for src in swift_sources:
        fid = file_refs[src]
        p = ref_path(src)
        lines.append(f"\t\t{fid} /* {os.path.basename(src)} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"{p}\"; sourceTree = \"<group>\"; }};")
    for m in objc_m_files:
        fid = file_refs[m]
        p = ref_path(m)
        lines.append(f"\t\t{fid} /* {os.path.basename(m)} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = \"{p}\"; sourceTree = \"<group>\"; }};")
    for c in c_files:
        fid = file_refs[c]
        p = ref_path(c)
        lines.append(f"\t\t{fid} /* {os.path.basename(c)} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.c.c; path = \"{p}\"; sourceTree = \"<group>\"; }};")
    for h in objc_h_files:
        fid = file_refs[h]
        p = ref_path(h)
        lines.append(f"\t\t{fid} /* {os.path.basename(h)} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = \"{p}\"; sourceTree = \"<group>\"; }};")
    # Bridging header
    lines.append(f"\t\t{bridge_id} /* {PROJECT_NAME}-Bridging-Header.h */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = \"{PROJECT_NAME}-Bridging-Header.h\"; sourceTree = \"<group>\"; }};")
    for res in resources:
        fid = file_refs[res]
        ext = os.path.splitext(res)[1]
        ftype = {'.html': 'text.html', '.json': 'text.json', '.js': 'sourcecode.javascript'}.get(ext, 'text')
        lines.append(f"\t\t{fid} /* {os.path.basename(res)} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; path = \"{os.path.basename(res)}\"; sourceTree = \"<group>\"; }};")
    # Assets.xcassets
    lines.append(f"\t\t{assets_id} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; }};")
    # Info.plist
    lines.append(f"\t\t{info_plist_id} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
    # Product
    lines.append(f"\t\t{product_ref_id} /* {PROJECT_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {PROJECT_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    lines.append("/* End PBXFileReference section */")
    lines.append("")

    # PBXFrameworksBuildPhase section
    lines.append("/* Begin PBXFrameworksBuildPhase section */")
    lines.append(f"\t\t{build_phase_frameworks_id} /* Frameworks */ = {{")
    lines.append("\t\t\tisa = PBXFrameworksBuildPhase;")
    lines.append("\t\t\tbuildActionMask = 2147483647;")
    lines.append("\t\t\tfiles = (")
    lines.append("\t\t\t);")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    lines.append("\t\t};")
    lines.append("/* End PBXFrameworksBuildPhase section */")
    lines.append("")

    # PBXGroup section
    lines.append("/* Begin PBXGroup section */")
    # 主 group
    lines.append(f"\t\t{main_group_id} = {{")
    lines.append("\t\t\tisa = PBXGroup;")
    lines.append("\t\t\tchildren = (")
    lines.append(f"\t\t\t\t{sources_group_id} /* {PROJECT_NAME} */,")
    lines.append(f"\t\t\t\t{exploits_group_id} /* Exploits */,")
    lines.append(f"\t\t\t\t{products_group_id} /* Products */,")
    lines.append("\t\t\t);")
    lines.append(f"\t\t\tsourceTree = \"<group>\";")
    lines.append("\t\t};")

    # MoyuTool 源码 group
    lines.append(f"\t\t{sources_group_id} /* {PROJECT_NAME} */ = {{")
    lines.append("\t\t\tisa = PBXGroup;")
    lines.append("\t\t\tchildren = (")
    for src in swift_sources:
        if "Exploits" not in src:
            lines.append(f"\t\t\t\t{file_refs[src]} /* {os.path.basename(src)} */,")
    lines.append(f"\t\t\t\t{bridge_id} /* {PROJECT_NAME}-Bridging-Header.h */,")
    lines.append(f"\t\t\t\t{resources_group_id} /* Resources */,")
    lines.append("\t\t\t);")
    lines.append(f"\t\t\tpath = {PROJECT_NAME};")
    lines.append("\t\t\tsourceTree = \"<group>\";")
    lines.append("\t\t};")

    # Resources group
    lines.append(f"\t\t{resources_group_id} /* Resources */ = {{")
    lines.append("\t\t\tisa = PBXGroup;")
    lines.append("\t\t\tchildren = (")
    lines.append(f"\t\t\t\t{info_plist_id} /* Info.plist */,")
    lines.append(f"\t\t\t\t{assets_id} /* Assets.xcassets */,")
    for res in resources:
        lines.append(f"\t\t\t\t{file_refs[res]} /* {os.path.basename(res)} */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tpath = Resources;")
    lines.append("\t\t\tsourceTree = \"<group>\";")
    lines.append("\t\t};")

    # Exploits group
    lines.append(f"\t\t{exploits_group_id} /* Exploits */ = {{")
    lines.append("\t\t\tisa = PBXGroup;")
    lines.append("\t\t\tchildren = (")
    for subdir in exploit_dirs:
        lines.append(f"\t\t\t\t{exploit_subgroup_ids[subdir]} /* {subdir} */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tpath = Exploits;")
    lines.append("\t\t\tsourceTree = \"<group>\";")
    lines.append("\t\t};")

    # Exploits 子 group
    for subdir, files in exploit_dirs.items():
        sgid = exploit_subgroup_ids[subdir]
        lines.append(f"\t\t{sgid} /* {subdir} */ = {{")
        lines.append("\t\t\tisa = PBXGroup;")
        lines.append("\t\t\tchildren = (")
        for src in files:
            lines.append(f"\t\t\t\t{file_refs[src]} /* {os.path.basename(src)} */,")
        lines.append("\t\t\t);")
        lines.append(f"\t\t\tpath = {subdir};")
        lines.append("\t\t\tsourceTree = \"<group>\";")
        lines.append("\t\t};")

    # Products group
    lines.append(f"\t\t{products_group_id} /* Products */ = {{")
    lines.append("\t\t\tisa = PBXGroup;")
    lines.append("\t\t\tchildren = (")
    lines.append(f"\t\t\t\t{product_ref_id} /* {PROJECT_NAME}.app */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tname = Products;")
    lines.append("\t\t\tsourceTree = \"<group>\";")
    lines.append("\t\t};")
    lines.append("/* End PBXGroup section */")
    lines.append("")

    # PBXNativeTarget section
    lines.append("/* Begin PBXNativeTarget section */")
    lines.append(f"\t\t{target_id} /* {PROJECT_NAME} */ = {{")
    lines.append("\t\t\tisa = PBXNativeTarget;")
    lines.append(f"\t\t\tbuildConfigurationList = {config_list_target_id} /* Build configuration list for PBXNativeTarget \"{PROJECT_NAME}\" */;")
    lines.append("\t\t\tbuildPhases = (")
    lines.append(f"\t\t\t\t{build_phase_sources_id} /* Sources */,")
    lines.append(f"\t\t\t\t{build_phase_frameworks_id} /* Frameworks */,")
    lines.append(f"\t\t\t\t{build_phase_resources_id} /* Resources */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tbuildRules = (")
    lines.append("\t\t\t);")
    lines.append("\t\t\tdependencies = (")
    lines.append("\t\t\t);")
    lines.append(f"\t\t\tname = {PROJECT_NAME};")
    lines.append("\t\t\tproductName = MoyuTool;")
    lines.append(f"\t\t\tproductReference = {product_ref_id} /* {PROJECT_NAME}.app */;")
    lines.append("\t\t\tproductType = \"com.apple.product-type.application\";")
    lines.append("\t\t};")
    lines.append("/* End PBXNativeTarget section */")
    lines.append("")

    # PBXProject section
    lines.append("/* Begin PBXProject section */")
    lines.append(f"\t\t{proj_id} /* Project object */ = {{")
    lines.append("\t\t\tisa = PBXProject;")
    lines.append("\t\t\tattributes = {")
    lines.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    lines.append("\t\t\t\tLastSwiftUpdateCheck = 1500;")
    lines.append("\t\t\t\tLastUpgradeCheck = 1500;")
    lines.append("\t\t\t\tTargetAttributes = {")
    lines.append(f"\t\t\t\t\t{target_id} = {{")
    lines.append("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
    lines.append("\t\t\t\t\t};")
    lines.append("\t\t\t\t};")
    lines.append("\t\t\t};")
    lines.append(f"\t\t\tbuildConfigurationList = {config_list_proj_id} /* Build configuration list for PBXProject \"{PROJECT_NAME}\" */;")
    lines.append("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    lines.append("\t\t\tdevelopmentRegion = en;")
    lines.append("\t\t\thasScannedForEncodings = 0;")
    lines.append("\t\t\tknownRegions = (")
    lines.append("\t\t\t\ten,")
    lines.append("\t\t\t\tBase,")
    lines.append("\t\t\t);")
    lines.append(f"\t\t\tmainGroup = {main_group_id};")
    lines.append(f"\t\t\tproductRefGroup = {products_group_id} /* Products */;")
    lines.append("\t\t\tprojectDirPath = \"\";")
    lines.append("\t\t\tprojectRoot = \"\";")
    lines.append("\t\t\ttargets = (")
    lines.append(f"\t\t\t\t{target_id} /* {PROJECT_NAME} */,")
    lines.append("\t\t\t);")
    lines.append("\t\t};")
    lines.append("/* End PBXProject section */")
    lines.append("")

    # PBXResourcesBuildPhase section
    lines.append("/* Begin PBXResourcesBuildPhase section */")
    lines.append(f"\t\t{build_phase_resources_id} /* Resources */ = {{")
    lines.append("\t\t\tisa = PBXResourcesBuildPhase;")
    lines.append("\t\t\tbuildActionMask = 2147483647;")
    lines.append("\t\t\tfiles = (")
    for res in resources:
        lines.append(f"\t\t\t\t{build_files[res]} /* {os.path.basename(res)} in Resources */,")
    lines.append(f"\t\t\t\t{build_files['Assets']} /* Assets.xcassets in Resources */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    lines.append("\t\t};")
    lines.append("/* End PBXResourcesBuildPhase section */")
    lines.append("")

    # PBXSourcesBuildPhase section
    lines.append("/* Begin PBXSourcesBuildPhase section */")
    lines.append(f"\t\t{build_phase_sources_id} /* Sources */ = {{")
    lines.append("\t\t\tisa = PBXSourcesBuildPhase;")
    lines.append("\t\t\tbuildActionMask = 2147483647;")
    lines.append("\t\t\tfiles = (")
    for src in swift_sources:
        lines.append(f"\t\t\t\t{build_files[src]} /* {os.path.basename(src)} in Sources */,")
    for m in objc_m_files:
        lines.append(f"\t\t\t\t{build_files[m]} /* {os.path.basename(m)} in Sources */,")
    for c in c_files:
        lines.append(f"\t\t\t\t{build_files[c]} /* {os.path.basename(c)} in Sources */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    lines.append("\t\t};")
    lines.append("/* End PBXSourcesBuildPhase section */")
    lines.append("")

    # XCBuildConfiguration section
    lines.append("/* Begin XCBuildConfiguration section */")
    # Project Debug
    lines.append(f"\t\t{config_debug_proj_id} /* Debug */ = {{")
    lines.append("\t\t\tisa = XCBuildConfiguration;")
    lines.append("\t\t\tbuildSettings = {")
    lines.append("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    lines.append("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    lines.append("\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
    lines.append("\t\t\t\tCOPY_PHASE_STRIP = NO;")
    lines.append("\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;")
    lines.append("\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;")
    lines.append("\t\t\t\tENABLE_TESTABILITY = YES;")
    lines.append("\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;")
    lines.append("\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;")
    lines.append("\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;")
    lines.append("\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;")
    lines.append("\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;")
    lines.append("\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;")
    lines.append("\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;")
    lines.append("\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;")
    lines.append(f"\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = {IOS_DEPLOYMENT_TARGET};")
    lines.append("\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;")
    lines.append("\t\t\t\tMTL_FAST_MATH = YES;")
    lines.append("\t\t\t\tONLY_ACTIVE_ARCH = YES;")
    lines.append("\t\t\t\tSDKROOT = iphoneos;")
    lines.append("\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;")
    lines.append("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";")
    lines.append("\t\t\t};")
    lines.append("\t\t\tname = Debug;")
    lines.append("\t\t};")
    # Project Release
    lines.append(f"\t\t{config_release_proj_id} /* Release */ = {{")
    lines.append("\t\t\tisa = XCBuildConfiguration;")
    lines.append("\t\t\tbuildSettings = {")
    lines.append("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    lines.append("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    lines.append("\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
    lines.append("\t\t\t\tCOPY_PHASE_STRIP = NO;")
    lines.append("\t\t\t\tDEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";")
    lines.append("\t\t\t\tENABLE_NS_ASSERTIONS = NO;")
    lines.append("\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;")
    lines.append("\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;")
    lines.append("\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;")
    lines.append("\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;")
    lines.append("\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;")
    lines.append("\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;")
    lines.append("\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;")
    lines.append("\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;")
    lines.append("\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;")
    lines.append(f"\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = {IOS_DEPLOYMENT_TARGET};")
    lines.append("\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;")
    lines.append("\t\t\t\tMTL_FAST_MATH = YES;")
    lines.append("\t\t\t\tSDKROOT = iphoneos;")
    lines.append("\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;")
    lines.append("\t\t\t\tVALIDATE_PRODUCT = YES;")
    lines.append("\t\t\t};")
    lines.append("\t\t\tname = Release;")
    lines.append("\t\t};")
    # 生成 HEADER_SEARCH_PATHS 字符串
    header_paths = "\t\t\t\t\t\"$(inherited)\",\n"
    for d in sorted(header_dirs):
        header_paths += f'\t\t\t\t\t"{d}",\n'

    # Target Debug
    lines.append(f"\t\t{config_debug_target_id} /* Debug */ = {{")
    lines.append("\t\t\tisa = XCBuildConfiguration;")
    lines.append("\t\t\tbuildSettings = {")
    lines.append(f"\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
    lines.append("\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
    lines.append(f"\t\t\t\tCODE_SIGN_STYLE = Automatic;")
    lines.append(f"\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    lines.append(f"\t\t\t\tGENERATE_INFOPLIST_FILE = YES;")
    lines.append(f"\t\t\t\tGCC_WARN_INHIBIT_ALL_WARNINGS = YES;")
    lines.append(f"\t\t\t\tHEADER_SEARCH_PATHS = (")
    lines.append(header_paths.rstrip())
    lines.append("\t\t\t\t);")
    lines.append(f"\t\t\t\tINFOPLIST_FILE = {PROJECT_NAME}/Resources/Info.plist;")
    lines.append(f"\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;")
    lines.append(f"\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;")
    lines.append(f"\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;")
    lines.append(f"\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = \"{APP_DISPLAY_NAME}\";")
    lines.append(f"\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = \"UIInterfaceOrientationPortrait\";")
    lines.append(f"\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = \"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight\";")
    lines.append(f"\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = {IOS_DEPLOYMENT_TARGET};")
    lines.append(f"\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
    lines.append("\t\t\t\t\t\"$(inherited)\",")
    lines.append("\t\t\t\t\t\"@executable_path/Frameworks\",")
    lines.append("\t\t\t\t);")
    lines.append(f"\t\t\t\tMARKETING_VERSION = 1.0.0;")
    lines.append(f"\t\t\t\tOTHER_LDFLAGS = (")
    lines.append("\t\t\t\t\t\"$(inherited)\",")
    lines.append("\t\t\t\t\t\"-framework\",")
    lines.append("\t\t\t\t\tIOKit,")
    lines.append("\t\t\t\t\t\"-framework\",")
    lines.append("\t\t\t\t\tIOSurface,")
    lines.append("\t\t\t\t\t\"-framework\",")
    lines.append("\t\t\t\t\tSecurity,")
    lines.append("\t\t\t\t\t\"-framework\",")
    lines.append("\t\t\t\t\tJavaScriptCore,")
    lines.append("\t\t\t\t\t\"-lz\",")
    lines.append("\t\t\t\t\t\"-lcompression\",")
    lines.append("\t\t\t\t);")
    lines.append(f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};")
    lines.append(f"\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    lines.append(f"\t\t\t\tSWIFT_OBJC_BRIDGING_HEADER = {PROJECT_NAME}/{PROJECT_NAME}-Bridging-Header.h;")
    lines.append("\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
    lines.append("\t\t\t\tSWIFT_VERSION = 5.0;")
    lines.append(f"\t\t\t\tTARGETED_DEVICE_FAMILY = \"1,2\";")
    lines.append("\t\t\t};")
    lines.append("\t\t\tname = Debug;")
    lines.append("\t\t};")
    # Target Release
    lines.append(f"\t\t{config_release_target_id} /* Release */ = {{")
    lines.append("\t\t\tisa = XCBuildConfiguration;")
    lines.append("\t\t\tbuildSettings = {")
    lines.append(f"\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
    lines.append("\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
    lines.append(f"\t\t\t\tCODE_SIGN_STYLE = Automatic;")
    lines.append(f"\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    lines.append(f"\t\t\t\tGENERATE_INFOPLIST_FILE = YES;")
    lines.append(f"\t\t\t\tGCC_WARN_INHIBIT_ALL_WARNINGS = YES;")
    lines.append(f"\t\t\t\tHEADER_SEARCH_PATHS = (")
    lines.append(header_paths.rstrip())
    lines.append("\t\t\t\t);")
    lines.append(f"\t\t\t\tINFOPLIST_FILE = {PROJECT_NAME}/Resources/Info.plist;")
    lines.append(f"\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;")
    lines.append(f"\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;")
    lines.append(f"\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;")
    lines.append(f"\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = \"{APP_DISPLAY_NAME}\";")
    lines.append(f"\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = \"UIInterfaceOrientationPortrait\";")
    lines.append(f"\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = \"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight\";")
    lines.append(f"\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = {IOS_DEPLOYMENT_TARGET};")
    lines.append(f"\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
    lines.append("\t\t\t\t\t\"$(inherited)\",")
    lines.append("\t\t\t\t\t\"@executable_path/Frameworks\",")
    lines.append("\t\t\t\t);")
    lines.append(f"\t\t\t\tMARKETING_VERSION = 1.0.0;")
    lines.append(f"\t\t\t\tOTHER_LDFLAGS = (")
    lines.append("\t\t\t\t\t\"$(inherited)\",")
    lines.append("\t\t\t\t\t\"-framework\",")
    lines.append("\t\t\t\t\tIOKit,")
    lines.append("\t\t\t\t\t\"-framework\",")
    lines.append("\t\t\t\t\tIOSurface,")
    lines.append("\t\t\t\t\t\"-framework\",")
    lines.append("\t\t\t\t\tSecurity,")
    lines.append("\t\t\t\t\t\"-framework\",")
    lines.append("\t\t\t\t\tJavaScriptCore,")
    lines.append("\t\t\t\t\t\"-lz\",")
    lines.append("\t\t\t\t\t\"-lcompression\",")
    lines.append("\t\t\t\t);")
    lines.append(f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};")
    lines.append(f"\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    lines.append(f"\t\t\t\tSWIFT_OBJC_BRIDGING_HEADER = {PROJECT_NAME}/{PROJECT_NAME}-Bridging-Header.h;")
    lines.append("\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
    lines.append("\t\t\t\tSWIFT_VERSION = 5.0;")
    lines.append(f"\t\t\t\tTARGETED_DEVICE_FAMILY = \"1,2\";")
    lines.append("\t\t\t};")
    lines.append("\t\t\tname = Release;")
    lines.append("\t\t};")
    lines.append("/* End XCBuildConfiguration section */")
    lines.append("")

    # XCConfigurationList section
    lines.append("/* Begin XCConfigurationList section */")
    lines.append(f"\t\t{config_list_proj_id} /* Build configuration list for PBXProject \"{PROJECT_NAME}\" */ = {{")
    lines.append("\t\t\tisa = XCConfigurationList;")
    lines.append("\t\t\tbuildConfigurations = (")
    lines.append(f"\t\t\t\t{config_debug_proj_id} /* Debug */,")
    lines.append(f"\t\t\t\t{config_release_proj_id} /* Release */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tdefaultConfigurationIsVisible = 0;")
    lines.append("\t\t\tdefaultConfigurationName = Release;")
    lines.append("\t\t};")
    lines.append(f"\t\t{config_list_target_id} /* Build configuration list for PBXNativeTarget \"{PROJECT_NAME}\" */ = {{")
    lines.append("\t\t\tisa = XCConfigurationList;")
    lines.append("\t\t\tbuildConfigurations = (")
    lines.append(f"\t\t\t\t{config_debug_target_id} /* Debug */,")
    lines.append(f"\t\t\t\t{config_release_target_id} /* Release */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tdefaultConfigurationIsVisible = 0;")
    lines.append("\t\t\tdefaultConfigurationName = Release;")
    lines.append("\t\t};")
    lines.append("/* End XCConfigurationList section */")
    lines.append("")

    lines.append("\t};")
    lines.append(f"\trootObject = {proj_id} /* Project object */;")
    lines.append("}")

    return "\n".join(lines) + "\n", target_id

if __name__ == "__main__":
    main()
