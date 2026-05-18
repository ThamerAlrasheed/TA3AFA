import re
import sys

def patch_pbxproj(file_path):
    with open(file_path, 'r') as f:
        content = f.read()

    # IDs to use
    build_file_id = "1F0000000000000000000001"
    package_ref_id = "1F0000000000000000000002"
    product_dep_id = "1F0000000000000000000003"

    if package_ref_id in content or "SDWebImageSwiftUI" in content:
        print("Already patched or SDWebImageSwiftUI already present.")
        return

    # 1. Add to PBXBuildFile section
    build_file_line = f"\t\t{build_file_id} /* SDWebImageSwiftUI in Frameworks */ = {{isa = PBXBuildFile; productRef = {product_dep_id} /* SDWebImageSwiftUI */; }};\n"
    content = content.replace("/* Begin PBXBuildFile section */\n", f"/* Begin PBXBuildFile section */\n{build_file_line}")

    # 2. Add to PBXFrameworksBuildPhase
    frameworks_phase_match = re.search(r'(040BD0CF2E4F8D9500E44F60 /\* Frameworks \*/ = \{[\s\S]*?files = \()([\s\S]*?)(\);)', content)
    if frameworks_phase_match:
        before = frameworks_phase_match.group(1)
        files = frameworks_phase_match.group(2)
        after = frameworks_phase_match.group(3)
        new_file = f"\n\t\t\t\t{build_file_id} /* SDWebImageSwiftUI in Frameworks */,"
        content = content[:frameworks_phase_match.start()] + before + files + new_file + "\n\t\t\t" + after + content[frameworks_phase_match.end():]
    
    # 3. Add to PBXNativeTarget MEDSAI packageProductDependencies
    target_match = re.search(r'(040BD0D12E4F8D9500E44F60 /\* MEDSAI \*/ = \{[\s\S]*?packageProductDependencies = \()([\s\S]*?)(\);)', content)
    if target_match:
        before = target_match.group(1)
        deps = target_match.group(2)
        after = target_match.group(3)
        new_dep = f"\n\t\t\t\t{product_dep_id} /* SDWebImageSwiftUI */,"
        content = content[:target_match.start()] + before + deps + new_dep + "\n\t\t\t" + after + content[target_match.end():]

    # 4. Add to PBXProject packageReferences
    project_match = re.search(r'(040BD0CA2E4F8D9500E44F60 /\* Project object \*/ = \{[\s\S]*?packageReferences = \()([\s\S]*?)(\);)', content)
    if project_match:
        before = project_match.group(1)
        refs = project_match.group(2)
        after = project_match.group(3)
        new_ref = f"\n\t\t\t\t{package_ref_id} /* XCRemoteSwiftPackageReference \"SDWebImageSwiftUI\" */,"
        content = content[:project_match.start()] + before + refs + new_ref + "\n\t\t\t" + after + content[project_match.end():]

    # 5. Add to XCRemoteSwiftPackageReference section
    package_ref_def = f"""\t\t{package_ref_id} /* XCRemoteSwiftPackageReference "SDWebImageSwiftUI" */ = {{
\t\t\tisa = XCRemoteSwiftPackageReference;
\t\t\trepositoryURL = "https://github.com/SDWebImage/SDWebImageSwiftUI";
\t\t\trequirement = {{
\t\t\t\tkind = upToNextMajorVersion;
\t\t\t\tminimumVersion = 3.0.0;
\t\t\t}};
\t\t}};
"""
    content = content.replace("/* Begin XCRemoteSwiftPackageReference section */\n", f"/* Begin XCRemoteSwiftPackageReference section */\n{package_ref_def}")

    # 6. Add to XCSwiftPackageProductDependency section
    product_dep_def = f"""\t\t{product_dep_id} /* SDWebImageSwiftUI */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {package_ref_id} /* XCRemoteSwiftPackageReference "SDWebImageSwiftUI" */;
\t\t\tproductName = SDWebImageSwiftUI;
\t\t}};
"""
    content = content.replace("/* Begin XCSwiftPackageProductDependency section */\n", f"/* Begin XCSwiftPackageProductDependency section */\n{product_dep_def}")

    with open(file_path, 'w') as f:
        f.write(content)

    print("Successfully patched project.pbxproj")

patch_pbxproj('/Users/mac/Desktop/TA3AFA/MEDSAI.xcodeproj/project.pbxproj')
