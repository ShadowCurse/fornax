import sys
sys.path.append("../thirdparty/vulkan-object/src")

from vulkan_object import get_vulkan_object, VulkanObject

def extension_to_toml(item):
    print("[[extension]]")
    print("name =", item.name)
    print("name_string =", item.nameString)
    print("spec_version_string =", item.specVersion)

    print("instance =", "true" if item.instance else "false")
    print("device =", "true" if item.device else "false")
    print("depends =", item.depends if item.depends else "null")
    print("vendor_tag =", item.vendorTag if item.vendorTag else "null")
    print("platform =", item.platform if item.platform else "null")
    print("protect =", item.protect if item.protect else "null")
    print("provisional =", "true" if item.provisional else "false")
    print("promoted_to =", item.promotedTo if item.promotedTo else "null")
    print("deprecated_by =", item.deprecatedBy if item.deprecatedBy else "null")
    print("obsoleted_by =", item.obsoletedBy if item.obsoletedBy else "null")
    print("special_use =", ",".join(item.specialUse))
    # ratified

    handles_names = [handle.name for handle in item.handles]
    print(f"handles = [", ",".join(handles_names), "]", sep = "")

    commands_names = [cmd.name for cmd in item.commands]
    print(f"commands = [", ",".join(commands_names), "]", sep = "")

    structs_names = [struct.name for struct in item.structs]
    print(f"structs = [", ",".join(structs_names), "]", sep = "")

    enums_names = [enum.name for enum in item.enums]
    print(f"enums = [", ",".join(enums_names), "]", sep = "")

    bitmasks_names = [bm.name for bm in item.bitmasks]
    print(f"bitmasks = [", ",".join(bitmasks_names), "]", sep = "")

    for (n, f) in item.flags.items():
        print("[[flags]]")
        print("flag =", n)
        names = [flag.name for flag in f]
        print(f"flags = [", ",".join(names), "]", sep = "")

    for (n, f) in item.enumFields.items():
        print("[[enum_fields]]")
        print("enum =", n)
        names = [i.name for i in f]
        print(f"fields = [", ",".join(names), "]", sep = "")

    for (n, f) in item.flagBits.items():
        print("[[flag_bits]]")
        print("flag =", n)
        names = [i.name for i in f]
        print(f"bits = [", ",".join(names), "]", sep = "")

    for fr in item.featureRequirement:
        print("[[feature_requirement]]")
        print("struct =", fr.struct)
        print("field =", fr.field)
        print("depends =", fr.depends if fr.depends else "null")

    print()

def version_to_toml(item):
    print("[[item]]")
    print("name =", item.name)
    print("api =", item.nameApi)
    print("api =", item.nameApi)
    for fr in item.featureRequirement:
        print("[[feature_requirement]]")
        print("struct =", fr.struct)
        print("field =", fr.field)
        print("depends =", fr.depends if fr.depends else "null")
    print()

def handle_to_toml(item):
    print("[[item]]")
    print("name =", item.name)
    print("aliases = [", ",".join(item.aliases), "]", sep = "")
    print("type =", item.type)
    print("protect =", item.protect if item.protect else "null")
    print("parent =", item.parent.name if item.parent else "null")
    print("instance =", "true" if item.instance else "false")
    print("devices =", "true" if item.device else "false")
    print("extensions = [", ",".join(item.extensions), "]", sep = "")
    print()

def command_to_toml(item):
    print("[[item]]")
    print("name =", item.name)
    print("alias =", item.alias if item.alias else "null")
    print("protect =", item.protect if item.protect else "null")
    print("version =", item.version.name if item.version else "null")
    print("instance =", "true" if handle.instance else "false")
    print("devices =", "true" if handle.device else "false")
    print("primary =", "true" if item.primary else "false")
    print("secondary =", "true" if item.secondary else "false")
    print("allow_no_queues =", "true" if item.allowNoQueues else "false")
    print("extensions = [", ",".join(handle.extensions), "]", sep = "")
    print("tasks = [", ",".join(item.tasks), "]", sep = "")
    print("queues = [", ",".join(item.queues), "]", sep = "")
    print("render_pass =", item.renderPass)
    print("video_conding =", item.videoCoding)

    print("return_type =", item.returnType)
    print("success_codes = [", ",".join(item.successCodes), "]", sep = "")
    print("error_codes = [", ",".join(item.errorCodes), "]", sep = "")
    print("implicit_extern_sync_params = [", ",".join(item.implicitExternSyncParams), "]", sep = "")
    for param in item.params:
        print("[[parameter]]")
        print("name =", param.name)
        print("alias =", param.alias)
        print("type =", param.type)
        print("full_type =", param.fullType)
        print("const =", "true" if param.const else "false")
        print("pointer =", "true" if param.pointer else "false")
        print("optional =", "true" if param.optional else "false")
        print("optional_pointer =", "true" if param.optionalPointer else "false")
        print("length =", param.length if param.length else "null")
        print("null_terminated =", "true" if param.nullTerminated else "false")
        print("array_size = [", ",".join(param.fixedSizeArray), "]", sep = "")
        print("extern_sync =", param.externSync)
        print("extern_sync_pointer =", param.externSyncPointer if param.externSyncPointer else "null")
    print()

def struct_to_toml(item):
    print("[[item]]")
    print(f"name = {item.name}")
    print(f"aliases = [", ",".join(item.aliases), "]", sep = "")
    print(f"extensions = [", ",".join(item.extensions), "]", sep = "")
    print("version =", item.version.name if item.version else "VK_VERSION_1_0")
    print("protect =", item.protect if item.protect else "null")
    print("union =", "true" if item.union else "false")
    # returnedOnly
    print("sType =", item.sType if item.sType else "null")
    print("allow_duplicate =", "true" if item.allowDuplicate else "false")
    print(f"extends = [", ",".join(item.extends), "]", sep = "")
    print(f"extended_by = [", ",".join(item.extendedBy), "]", sep = "")

    for member in item.members:
        print("[[member]]")
        print(f"name = {member.name}")
        print(f"type = {member.type}")
        print(f"full_type = {member.fullType}")
        # noAutoValidity
        print("limit_type =", member.limitType if member.limitType else "null")
        print("const =", "true" if member.const else "false")
        print("pointer =", "true" if member.pointer else "false")
        print(f"array_size = [", ",".join(member.fixedSizeArray), "]", sep = "")
        print("optional =", "true" if member.optional else "false")
        print("optional_ptr =", "true" if member.optionalPointer else "false")
        print("extern_sync =", member.externSync)
        # cDeclaration
        print("bits =", f"{member.bitFieldWidth}" if member.bitFieldWidth else "null")
        print("selector =", member.selector if member.selector else "null")
        print(f"selection = [", ",".join(member.selection), "]", sep = "")

    print()

def enum_to_toml(item):
    print("[[enum]]")
    print(f"name =", item.name)
    print(f"aliases = [", ",".join(item.aliases), "]", sep = "")
    print("protect =", item.protect if item.protect else "null")
    print("bitwidth =", item.bitWidth)
    print("return_only =", "true" if item.returnedOnly else "false")
    print(f"extensions = [", ",".join(item.extensions), "]", sep = "")
    print(f"field_extensions = [", ",".join(item.fieldExtensions), "]", sep = "")

    for m in item.fields:
        print("[[field]]")
        print(f"name =", m.name)
        print(f"aliases = [", ",".join(m.aliases), "]", sep = "")
        print("negative =", "true" if m.negative else "false")
        print(f"value =", m.value)
        print(f"extensions = [", ",".join(m.extensions), "]", sep = "")
    print()

def bitmask_to_toml(item):
    print("[[bitmask]]")
    print(f"name =", item.name)
    print(f"aliases = [", ",".join(item.aliases), "]", sep = "")
    print("protect =", item.protect if item.protect else "null")
    print(f"flags_name =", item.flagName)
    print("bitwidth =", item.bitWidth)
    print("return_only =", "true" if item.returnedOnly else "false")
    print(f"extensions = [", ",".join(item.extensions), "]", sep = "")
    print(f"flag_extensions = [", ",".join(item.flagExtensions), "]", sep = "")

    for m in item.flags:
        print("[[flag]]")
        print(f"name =", m.name)
        print(f"aliases = [", ",".join(m.aliases), "]", sep = "")
        print("protect =", m.protect if m.protect else "null")
        print(f"value =", m.value)
        print("multibit =", "true" if m.multiBit else "false")
        print("zero =", "true" if m.zero else "false")
        print(f"extensions = [", ",".join(m.extensions), "]", sep = "")
    print()

def flags_to_toml(item):
    print("[[flags]]")
    print(f"name =", item.name)
    print(f"aliases = [", ",".join(item.aliases), "]", sep = "")
    print("bitmask_name =", item.bitmaskName if item.bitmaskName else "null")
    print("protect =", item.protect if item.protect else "null")
    print(f"base_flags_type =", item.baseFlagsType)
    print("bitwidth =", item.bitWidth)
    print("return_only =", "true" if item.returnedOnly else "false")
    print(f"extensions = [", ",".join(item.extensions), "]", sep = "")
    print()

def constant_to_toml(item):
    print("[[constant]]")
    print(f"name =", item.name)
    print(f"type =", item.type)
    print(f"value =", item.value)
    print()

def spirv_to_toml(item):
    if item.extension:
        print("[[spirv_extension]]")
    else:
        print("[[spirv_capability]]")
    print(f"name =", item.name)
    for m in item.enable:
        print("[[enable]]")
        print("version =", m.version if m.version else "null")
        print("extension =", m.extension if m.extension else "null")
        print("struct =", m.struct if m.struct else "null")
        print("feature =", m.feature if m.feature else "null")
        print("requires =", m.requires if m.requires else "null")
        print("property =", m.property if m.property else "null")
        print("member =", m.member if m.member else "null")
        print("value =", m.value if m.value else "null")
    print()


vk = get_vulkan_object()

for ext in vk.extensions.values():
    extension_to_toml(ext)

for version in vk.versions.values():
    version_to_toml(version)

for handle in vk.handles.values():
    handle_to_toml(handle)

for command in vk.commands.values():
    command_to_toml(command)

for struct in vk.structs.values():
    struct_to_toml(struct)

for enum in vk.enums.values():
    enum_to_toml(enum)

for bitmask in vk.bitmasks.values():
    bitmask_to_toml(bitmask)

for flags in vk.flags.values():
    flags_to_toml(flags)

for constant in vk.constants.values():
    constant_to_toml(constant)

for f in vk.formats.values():
    pass

for ss in vk.syncStage:
    pass

for sa in vk.syncAccess:
    pass

for sp in vk.syncPipeline:
    pass

for s in vk.spirv:
    spirv_to_toml(s)

for (name, ext) in vk.platforms.items():
    print("[[platform]]")
    print(f"name = {name}")
    print(f"ext = {ext}")
    print()

print("[vendor_tags]")
print(f"tags = [", ",".join(vk.vendorTags), "]", sep = "")
print()

for f in vk.videoCodecs.values():
    pass
