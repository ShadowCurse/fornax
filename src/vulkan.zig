// Copyright (c) 2025 Egor Lazarchuk
//
// Based in part on Fossilize project which is:
// Copyright (c) 2025 Hans-Kristian Arntzen
//
// SPDX-License-Identifier: MIT

const std = @import("std");
const vk = @import("volk");
const a = @import("spirv");
const log = @import("log.zig");
const vv = @import("vulkan_validation.zig");
const PDF = @import("physical_device_features.zig");

const Allocator = std.mem.Allocator;

const VK_VALIDATION_LAYERS_NAMES = [_][*c]const u8{"VK_LAYER_KHRONOS_validation"};
const VK_ADDITIONAL_EXTENSIONS_NAMES = [_][*c]const u8{"VK_EXT_debug_utils"};

pub fn contains_all_extensions(
    log_prefix: ?[]const u8,
    extensions: []const vk.VkExtensionProperties,
    to_find: []const [*c]const u8,
) bool {
    var found_extensions: u32 = 0;
    for (extensions) |e| {
        var required = "--------";
        for (to_find) |tf| {
            const extension_name_span = std.mem.span(@as(
                [*c]const u8,
                @ptrCast(&e.extensionName),
            ));
            const tf_extension_name_span = std.mem.span(@as(
                [*c]const u8,
                tf,
            ));
            if (std.mem.eql(u8, extension_name_span, tf_extension_name_span)) {
                found_extensions += 1;
                required = "required";
            }
        }
        if (log_prefix) |lp|
            log.debug(@src(), "({s})({s}) Extension version: {d}.{d}.{d} Name: {s}", .{
                required,
                lp,
                vk.VK_API_VERSION_MAJOR(e.specVersion),
                vk.VK_API_VERSION_MINOR(e.specVersion),
                vk.VK_API_VERSION_PATCH(e.specVersion),
                e.extensionName,
            });
    }
    return found_extensions == to_find.len;
}

pub fn contains_all_layers(
    log_prefix: ?[]const u8,
    layers: []const vk.VkLayerProperties,
    to_find: []const [*c]const u8,
) bool {
    var found_layers: u32 = 0;
    for (layers) |l| {
        var required = "--------";
        for (to_find) |tf| {
            const layer_name_span = std.mem.span(@as([*c]const u8, @ptrCast(&l.layerName)));
            const tf_layer_name_span = std.mem.span(@as([*c]const u8, tf));
            if (std.mem.eql(u8, layer_name_span, tf_layer_name_span)) {
                found_layers += 1;
                required = "required";
            }
        }
        if (log_prefix) |lp|
            log.debug(@src(), "({s})({s}) Layer name: {s} Spec version: {d}.{d}.{d} Description: {s}", .{
                required,
                lp,
                l.layerName,
                vk.VK_API_VERSION_MAJOR(l.specVersion),
                vk.VK_API_VERSION_MINOR(l.specVersion),
                vk.VK_API_VERSION_PATCH(l.specVersion),
                l.description,
            });
    }
    return found_layers == to_find.len;
}

pub fn get_instance_extensions(arena_alloc: Allocator) ![]const vk.VkExtensionProperties {
    var extensions_count: u32 = 0;
    try vv.check_result(vk.vkEnumerateInstanceExtensionProperties.?(
        null,
        &extensions_count,
        null,
    ));
    const extensions = try arena_alloc.alloc(vk.VkExtensionProperties, extensions_count);
    try vv.check_result(vk.vkEnumerateInstanceExtensionProperties.?(
        null,
        &extensions_count,
        extensions.ptr,
    ));
    return extensions;
}

pub fn get_instance_layer_properties(arena_alloc: Allocator) ![]const vk.VkLayerProperties {
    var layer_property_count: u32 = 0;
    try vv.check_result(vk.vkEnumerateInstanceLayerProperties.?(&layer_property_count, null));
    const layers = try arena_alloc.alloc(vk.VkLayerProperties, layer_property_count);
    try vv.check_result(vk.vkEnumerateInstanceLayerProperties.?(
        &layer_property_count,
        layers.ptr,
    ));
    return layers;
}

pub const Instance = struct {
    instance: vk.VkInstance,
    api_version: u32,
    has_properties_2: bool,
    all_extension_names: []const [*c]const u8,
};
pub fn create_vk_instance(
    arena_alloc: Allocator,
    requested_app_info: ?*const vk.VkApplicationInfo,
    enable_validation: bool,
) !Instance {
    const api_version = vk.volkGetInstanceVersion();
    log.info(
        @src(),
        "Supported vulkan version: {d}.{d}.{d}",
        .{
            vk.VK_API_VERSION_MAJOR(api_version),
            vk.VK_API_VERSION_MINOR(api_version),
            vk.VK_API_VERSION_PATCH(api_version),
        },
    );
    if (requested_app_info) |app_info| {
        log.info(
            @src(),
            "Requested app info vulkan version: {d}.{d}.{d}",
            .{
                vk.VK_API_VERSION_MAJOR(app_info.apiVersion),
                vk.VK_API_VERSION_MINOR(app_info.apiVersion),
                vk.VK_API_VERSION_PATCH(app_info.apiVersion),
            },
        );
        if (api_version < app_info.apiVersion) {
            log.err(@src(), "Requested vulkan api version is above the supported version", .{});
            return error.UnsupportedVulkanApiVersion;
        }
    }

    const extensions = try get_instance_extensions(arena_alloc);
    if (!contains_all_extensions("Instance", extensions, &VK_ADDITIONAL_EXTENSIONS_NAMES))
        return error.AdditionalExtensionsNotFound;

    const has_properties_2 = contains_all_extensions(
        null,
        extensions,
        &.{vk.VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME},
    );

    const all_extension_names = try arena_alloc.alloc([*c]const u8, extensions.len);
    for (extensions, 0..) |*e, i|
        all_extension_names[i] = &e.extensionName;

    const enabled_layers = if (enable_validation) blk: {
        const layers = try get_instance_layer_properties(arena_alloc);
        if (!contains_all_layers("Instance", layers, &VK_VALIDATION_LAYERS_NAMES))
            return error.InstanceValidationLayersNotFound;
        break :blk &VK_VALIDATION_LAYERS_NAMES;
    } else &.{};

    const app_info = if (requested_app_info) |app_info|
        app_info
    else
        &vk.VkApplicationInfo{
            .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName = "glacier",
            .applicationVersion = vk.VK_MAKE_VERSION(0, 0, 1),
            .pEngineName = "glacier",
            .engineVersion = vk.VK_MAKE_VERSION(0, 0, 1),
            .apiVersion = api_version,
            .pNext = null,
        };
    log.info(@src(), "Creating instance with application name: {s} engine name: {s} api version: {d}.{d}.{d}", .{
        app_info.pApplicationName,
        app_info.pEngineName,
        vk.VK_API_VERSION_MAJOR(app_info.apiVersion),
        vk.VK_API_VERSION_MINOR(app_info.apiVersion),
        vk.VK_API_VERSION_PATCH(app_info.apiVersion),
    });
    const instance_create_info = vk.VkInstanceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = app_info,
        .ppEnabledExtensionNames = all_extension_names.ptr,
        .enabledExtensionCount = @as(u32, @intCast(all_extension_names.len)),
        .ppEnabledLayerNames = @ptrCast(enabled_layers.ptr),
        .enabledLayerCount = @as(u32, @intCast(enabled_layers.len)),
    };

    var vk_instance: vk.VkInstance = undefined;
    try vv.check_result(vk.vkCreateInstance.?(&instance_create_info, null, &vk_instance));
    log.debug(
        @src(),
        "Created instance api version: {d}.{d}.{d} has_properties_2: {}",
        .{
            vk.VK_API_VERSION_MAJOR(api_version),
            vk.VK_API_VERSION_MINOR(api_version),
            vk.VK_API_VERSION_PATCH(api_version),
            has_properties_2,
        },
    );
    return .{
        .instance = vk_instance,
        .api_version = api_version,
        .has_properties_2 = has_properties_2,
        .all_extension_names = all_extension_names,
    };
}

pub fn init_debug_callback(instance: vk.VkInstance) !vk.VkDebugReportCallbackEXT {
    const create_info = vk.VkDebugReportCallbackCreateInfoEXT{
        .sType = vk.VK_STRUCTURE_TYPE_DEBUG_REPORT_CALLBACK_CREATE_INFO_EXT,
        .pfnCallback = debug_callback,
        .flags = vk.VK_DEBUG_REPORT_ERROR_BIT_EXT |
            vk.VK_DEBUG_REPORT_WARNING_BIT_EXT,
        .pUserData = null,
    };

    var callback: vk.VkDebugReportCallbackEXT = undefined;
    try vv.check_result(
        vk.vkCreateDebugReportCallbackEXT.?(
            instance,
            &create_info,
            null,
            &callback,
        ),
    );
    return callback;
}

pub fn debug_callback(
    flags: vk.VkDebugReportFlagsEXT,
    _: vk.VkDebugReportObjectTypeEXT,
    _: u64,
    _: usize,
    _: i32,
    layer: [*c]const u8,
    message: [*c]const u8,
    _: ?*anyopaque,
) callconv(.c) vk.VkBool32 {
    if (flags & vk.VK_DEBUG_REPORT_WARNING_BIT_EXT != 0)
        log.warn(@src(), "Layer: {s} Message: {s}", .{ layer, message });
    if (flags & vk.VK_DEBUG_REPORT_ERROR_BIT_EXT != 0)
        log.err(@src(), "Layer: {s} Message: {s}", .{ layer, message });

    return vk.VK_FALSE;
}

pub fn get_physical_devices(
    arena_alloc: Allocator,
    vk_instance: vk.VkInstance,
) ![]const vk.VkPhysicalDevice {
    var physical_device_count: u32 = 0;
    try vv.check_result(vk.vkEnumeratePhysicalDevices.?(
        vk_instance,
        &physical_device_count,
        null,
    ));
    const physical_devices = try arena_alloc.alloc(
        vk.VkPhysicalDevice,
        physical_device_count,
    );
    try vv.check_result(vk.vkEnumeratePhysicalDevices.?(
        vk_instance,
        &physical_device_count,
        physical_devices.ptr,
    ));
    return physical_devices;
}

pub fn get_physical_device_exensions(
    arena_alloc: Allocator,
    physical_device: vk.VkPhysicalDevice,
    extension_name: [*c]const u8,
) ![]const vk.VkExtensionProperties {
    var extensions_count: u32 = 0;
    try vv.check_result(vk.vkEnumerateDeviceExtensionProperties.?(
        physical_device,
        extension_name,
        &extensions_count,
        null,
    ));
    const extensions = try arena_alloc.alloc(vk.VkExtensionProperties, extensions_count);
    try vv.check_result(vk.vkEnumerateDeviceExtensionProperties.?(
        physical_device,
        extension_name,
        &extensions_count,
        extensions.ptr,
    ));
    return extensions;
}

pub fn get_physical_device_layers(
    arena_alloc: Allocator,
    physical_device: vk.VkPhysicalDevice,
) ![]const vk.VkLayerProperties {
    var layer_property_count: u32 = 0;
    try vv.check_result(vk.vkEnumerateDeviceLayerProperties.?(
        physical_device,
        &layer_property_count,
        null,
    ));
    const layers = try arena_alloc.alloc(vk.VkLayerProperties, layer_property_count);
    try vv.check_result(vk.vkEnumerateDeviceLayerProperties.?(
        physical_device,
        &layer_property_count,
        layers.ptr,
    ));
    return layers;
}

pub const PhysicalDevice = struct {
    device: vk.VkPhysicalDevice,
    graphics_queue_family: u32,
    has_validation_cache: bool,
};

pub fn select_physical_device(
    arena_alloc: Allocator,
    vk_instance: vk.VkInstance,
    enable_validation: bool,
) !PhysicalDevice {
    const physical_devices = try get_physical_devices(arena_alloc, vk_instance);

    for (physical_devices) |physical_device| {
        var properties: vk.VkPhysicalDeviceProperties = undefined;
        vk.vkGetPhysicalDeviceProperties.?(physical_device, &properties);

        log.debug(@src(),
            \\ Physical device:
            \\    Name: {s}
            \\    API version: {d}.{d}.{d}
            \\    Driver version: {d}.{d}.{d}
            \\    Vendor ID: {d}
            \\    Device Id: {d}
            \\    Device type: {d}
        , .{
            properties.deviceName,
            vk.VK_API_VERSION_MAJOR(properties.apiVersion),
            vk.VK_API_VERSION_MINOR(properties.apiVersion),
            vk.VK_API_VERSION_PATCH(properties.apiVersion),
            vk.VK_API_VERSION_MAJOR(properties.driverVersion),
            vk.VK_API_VERSION_MINOR(properties.driverVersion),
            vk.VK_API_VERSION_PATCH(properties.driverVersion),
            properties.vendorID,
            properties.deviceID,
            properties.deviceType,
        });

        const has_validation_cache = if (enable_validation) blk: {
            const layers = try get_physical_device_layers(arena_alloc, physical_device);
            if (!contains_all_layers(&properties.deviceName, layers, &VK_VALIDATION_LAYERS_NAMES))
                return error.PhysicalDeviceValidationLayersNotFound;

            const validation_extensions = try get_physical_device_exensions(
                arena_alloc,
                physical_device,
                "VK_LAYER_KHRONOS_validation",
            );
            break :blk contains_all_extensions(
                null,
                validation_extensions,
                &.{vk.VK_EXT_VALIDATION_CACHE_EXTENSION_NAME},
            );
        } else false;

        // Because the exact queue does not matter much,
        // select the first queue with graphics capability.
        var queue_family_count: u32 = 0;
        vk.vkGetPhysicalDeviceQueueFamilyProperties.?(physical_device, &queue_family_count, null);
        const queue_families = try arena_alloc.alloc(
            vk.VkQueueFamilyProperties,
            queue_family_count,
        );
        vk.vkGetPhysicalDeviceQueueFamilyProperties.?(
            physical_device,
            &queue_family_count,
            queue_families.ptr,
        );
        var graphics_queue_family: ?u32 = null;
        for (queue_families, 0..) |qf, i| {
            if (qf.queueFlags & vk.VK_QUEUE_GRAPHICS_BIT != 0) {
                graphics_queue_family = @intCast(i);
                break;
            }
        }

        if (graphics_queue_family != null) {
            log.debug(
                @src(),
                "Selected device: {s} Graphics queue family: {d} Has validation cache: {}",
                .{
                    properties.deviceName,
                    graphics_queue_family.?,
                    has_validation_cache,
                },
            );
            return .{
                .device = physical_device,
                .graphics_queue_family = graphics_queue_family.?,
                .has_validation_cache = has_validation_cache,
            };
        }
    }
    return error.PhysicalDeviceNotSelected;
}

pub fn usable_device_extension(
    ext: [*c]const u8,
    all_ext_props: []const vk.VkExtensionProperties,
    api_version: u32,
) bool {
    const e = std.mem.span(ext);
    if (std.mem.eql(u8, e, vk.VK_AMD_NEGATIVE_VIEWPORT_HEIGHT_EXTENSION_NAME))
        // illigal to enable with maintenance1
        return false;
    if (std.mem.eql(u8, e, vk.VK_NV_RAY_TRACING_EXTENSION_NAME))
        // causes problems with pipeline replaying
        return false;
    if (std.mem.eql(u8, e, vk.VK_AMD_SHADER_INFO_EXTENSION_NAME))
        // Mesa disables shader cache when thisi is enabled.
        return false;
    if (std.mem.eql(u8, e, vk.VK_EXT_BUFFER_DEVICE_ADDRESS_EXTENSION_NAME))
        for (all_ext_props) |other_ext| {
            const other_e = std.mem.span(@as([*c]const u8, @ptrCast(&other_ext.extensionName)));
            if (std.mem.eql(u8, other_e, vk.VK_KHR_BUFFER_DEVICE_ADDRESS_EXTENSION_NAME))
                return false;
        };
    if (std.mem.eql(u8, e, vk.VK_AMD_SHADER_FRAGMENT_MASK_EXTENSION_NAME))
        for (all_ext_props) |other_ext| {
            const other_e = std.mem.span(@as([*c]const u8, @ptrCast(&other_ext.extensionName)));
            if (std.mem.eql(u8, other_e, vk.VK_EXT_DESCRIPTOR_BUFFER_EXTENSION_NAME))
                return false;
        };

    const VK_1_1_EXTS: []const []const u8 = &.{
        vk.VK_KHR_SHADER_SUBGROUP_EXTENDED_TYPES_EXTENSION_NAME,
        vk.VK_KHR_SPIRV_1_4_EXTENSION_NAME,
        vk.VK_KHR_SHARED_PRESENTABLE_IMAGE_EXTENSION_NAME,
        vk.VK_KHR_SHADER_FLOAT_CONTROLS_EXTENSION_NAME,
        vk.VK_KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME,
        vk.VK_KHR_RAY_TRACING_PIPELINE_EXTENSION_NAME,
        vk.VK_KHR_RAY_QUERY_EXTENSION_NAME,
        vk.VK_KHR_MAINTENANCE_4_EXTENSION_NAME,
        vk.VK_KHR_SHADER_SUBGROUP_UNIFORM_CONTROL_FLOW_EXTENSION_NAME,
        vk.VK_EXT_SUBGROUP_SIZE_CONTROL_EXTENSION_NAME,
        vk.VK_NV_SHADER_SM_BUILTINS_EXTENSION_NAME,
        vk.VK_NV_SHADER_SUBGROUP_PARTITIONED_EXTENSION_NAME,
        vk.VK_NV_DEVICE_GENERATED_COMMANDS_EXTENSION_NAME,
    };

    var is_vk_1_1_ext: bool = false;
    for (VK_1_1_EXTS) |vk_1_1_ext|
        if (std.mem.eql(u8, vk_1_1_ext, e)) {
            is_vk_1_1_ext = true;
            break;
        };

    if (api_version < vk.VK_API_VERSION_1_1 and is_vk_1_1_ext) {
        return false;
    }

    return true;
}

fn find_pnext(stype: u32, item: ?*const anyopaque) ?*anyopaque {
    var pnext: ?*const vk.VkBaseInStructure = @ptrCast(@alignCast(item));
    while (pnext) |next| {
        pnext = next.pNext;
        if (next.sType == stype) return @ptrCast(@constCast(next));
    }
    return null;
}

fn filter_features(
    current_features: *vk.VkPhysicalDeviceFeatures2,
    other_features: *PDF,
    wanted_features: ?*const vk.VkPhysicalDeviceFeatures2,
) void {
    const Inner = struct {
        fn reset(item: anytype) void {
            const child = @typeInfo(@TypeOf(item)).pointer.child;
            const type_info = @typeInfo(child).@"struct";
            inline for (type_info.fields) |field| {
                if (field.type == vk.VkBool32) @field(item, field.name) = vk.VK_FALSE;
            }
        }
    };
    // These feature bits conflict according to validation layers.
    if (other_features.vk_physical_device_fragment_shading_rate_features_khr.pipelineFragmentShadingRate == vk.VK_TRUE or
        other_features.vk_physical_device_fragment_shading_rate_features_khr.attachmentFragmentShadingRate == vk.VK_TRUE or
        other_features.vk_physical_device_fragment_shading_rate_features_khr.primitiveFragmentShadingRate == vk.VK_TRUE)
    {
        // other_features.shading_rate_nv.shadingRateImage = false;
        // other_features.shading_rate_nv.shadingRateCoarseSampleOrder = false;
        other_features.vk_physical_device_fragment_density_map_features_ext.fragmentDensityMap =
            vk.VK_FALSE;
    }

    // Only enable robustness if requested since it affects compilation on most implementations.
    if (wanted_features) |wf| {
        current_features.features.robustBufferAccess =
            current_features.features.robustBufferAccess & wf.features.robustBufferAccess;

        if (find_pnext(
            vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT,
            wf.pNext,
        )) |item| {
            const robustness2: *const vk.VkPhysicalDeviceRobustness2FeaturesEXT =
                @ptrCast(@alignCast(item));
            other_features
                .vk_physical_device_robustness_2_features_ext.robustBufferAccess2 =
                other_features
                    .vk_physical_device_robustness_2_features_ext.robustBufferAccess2 &
                robustness2.robustBufferAccess2;
            other_features
                .vk_physical_device_robustness_2_features_ext.robustImageAccess2 =
                other_features
                    .vk_physical_device_robustness_2_features_ext.robustImageAccess2 &
                robustness2.robustImageAccess2;
            other_features
                .vk_physical_device_robustness_2_features_ext.nullDescriptor =
                other_features
                    .vk_physical_device_robustness_2_features_ext.nullDescriptor &
                robustness2.nullDescriptor;
        } else Inner.reset(&other_features.vk_physical_device_robustness_2_features_ext);

        if (find_pnext(
            vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_ROBUSTNESS_FEATURES_EXT,
            wf.pNext,
        )) |item| {
            const image_robustness: *const vk.VkPhysicalDeviceImageRobustnessFeaturesEXT =
                @ptrCast(@alignCast(item));
            other_features
                .vk_physical_device_image_robustness_features_ext.robustImageAccess =
                other_features
                    .vk_physical_device_image_robustness_features_ext.robustImageAccess &
                image_robustness.robustImageAccess;
        } else Inner.reset(&other_features.vk_physical_device_image_robustness_features_ext);

        if (find_pnext(
            vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_ENUMS_FEATURES_NV,
            wf.pNext,
        )) |item| {
            const fragment_shading_rate_enums: *const vk.VkPhysicalDeviceFragmentShadingRateEnumsFeaturesNV =
                @ptrCast(@alignCast(item));
            other_features
                .vk_physical_device_fragment_shading_rate_enums_features_nv
                .fragmentShadingRateEnums =
                other_features
                    .vk_physical_device_fragment_shading_rate_enums_features_nv
                    .fragmentShadingRateEnums &
                fragment_shading_rate_enums.fragmentShadingRateEnums;

            other_features
                .vk_physical_device_fragment_shading_rate_enums_features_nv
                .noInvocationFragmentShadingRates =
                other_features.vk_physical_device_fragment_shading_rate_enums_features_nv
                    .noInvocationFragmentShadingRates &
                fragment_shading_rate_enums.noInvocationFragmentShadingRates;

            other_features
                .vk_physical_device_fragment_shading_rate_enums_features_nv
                .supersampleFragmentShadingRates =
                other_features
                    .vk_physical_device_fragment_shading_rate_enums_features_nv
                    .supersampleFragmentShadingRates &
                fragment_shading_rate_enums.supersampleFragmentShadingRates;
        } else Inner.reset(&other_features.vk_physical_device_fragment_shading_rate_enums_features_nv);

        if (find_pnext(
            vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_FEATURES_KHR,
            wf.pNext,
        )) |item| {
            const fragment_shading_rate: *const vk.VkPhysicalDeviceFragmentShadingRateFeaturesKHR =
                @ptrCast(@alignCast(item));
            other_features.vk_physical_device_fragment_shading_rate_features_khr
                .pipelineFragmentShadingRate =
                other_features.vk_physical_device_fragment_shading_rate_features_khr
                    .pipelineFragmentShadingRate &
                fragment_shading_rate.pipelineFragmentShadingRate;
            other_features.vk_physical_device_fragment_shading_rate_features_khr
                .primitiveFragmentShadingRate =
                other_features.vk_physical_device_fragment_shading_rate_features_khr
                    .primitiveFragmentShadingRate &
                fragment_shading_rate.primitiveFragmentShadingRate;
            other_features.vk_physical_device_fragment_shading_rate_features_khr
                .attachmentFragmentShadingRate =
                other_features.vk_physical_device_fragment_shading_rate_features_khr
                    .attachmentFragmentShadingRate &
                fragment_shading_rate.attachmentFragmentShadingRate;
        } else Inner.reset(&other_features.vk_physical_device_fragment_shading_rate_features_khr);

        if (find_pnext(
            vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_EXT,
            wf.pNext,
        )) |item| {
            const mesh_shader: *const vk.VkPhysicalDeviceMeshShaderFeaturesEXT =
                @ptrCast(@alignCast(item));
            other_features.vk_physical_device_mesh_shader_features_ext.taskShader =
                other_features.vk_physical_device_mesh_shader_features_ext.taskShader &
                mesh_shader.taskShader;
            other_features.vk_physical_device_mesh_shader_features_ext.meshShader =
                other_features.vk_physical_device_mesh_shader_features_ext.meshShader &
                mesh_shader.meshShader;
            other_features.vk_physical_device_mesh_shader_features_ext.multiviewMeshShader =
                other_features.vk_physical_device_mesh_shader_features_ext.multiviewMeshShader &
                mesh_shader.multiviewMeshShader;
            other_features.vk_physical_device_mesh_shader_features_ext.meshShaderQueries =
                other_features.vk_physical_device_mesh_shader_features_ext.meshShaderQueries &
                mesh_shader.meshShaderQueries;
            other_features.vk_physical_device_mesh_shader_features_ext
                .primitiveFragmentShadingRateMeshShader =
                other_features.vk_physical_device_mesh_shader_features_ext
                    .primitiveFragmentShadingRateMeshShader &
                other_features.vk_physical_device_fragment_shading_rate_features_khr
                    .primitiveFragmentShadingRate &
                mesh_shader.primitiveFragmentShadingRateMeshShader;
        } else Inner.reset(&other_features.vk_physical_device_mesh_shader_features_ext);

        if (find_pnext(
            vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_NV,
            wf.pNext,
        )) |item| {
            const mesh_shader_nv: *const vk.VkPhysicalDeviceMeshShaderFeaturesNV =
                @ptrCast(@alignCast(item));
            other_features.vk_physical_device_mesh_shader_features_nv.taskShader =
                other_features.vk_physical_device_mesh_shader_features_nv.taskShader &
                mesh_shader_nv.taskShader;
            other_features.vk_physical_device_mesh_shader_features_nv.meshShader =
                other_features.vk_physical_device_mesh_shader_features_nv.meshShader &
                mesh_shader_nv.meshShader;
        } else Inner.reset(&other_features.vk_physical_device_mesh_shader_features_nv);

        if (find_pnext(
            vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_FEATURES_EXT,
            wf.pNext,
        )) |item| {
            const descriptor_buffer: *const vk.VkPhysicalDeviceDescriptorBufferFeaturesEXT =
                @ptrCast(@alignCast(item));
            other_features.vk_physical_device_descriptor_buffer_features_ext.descriptorBuffer =
                other_features.vk_physical_device_descriptor_buffer_features_ext
                    .descriptorBuffer &
                descriptor_buffer.descriptorBuffer;
            other_features.vk_physical_device_descriptor_buffer_features_ext
                .descriptorBufferCaptureReplay =
                other_features.vk_physical_device_descriptor_buffer_features_ext
                    .descriptorBufferCaptureReplay &
                descriptor_buffer.descriptorBufferCaptureReplay;
            other_features.vk_physical_device_descriptor_buffer_features_ext
                .descriptorBufferImageLayoutIgnored =
                other_features.vk_physical_device_descriptor_buffer_features_ext
                    .descriptorBufferImageLayoutIgnored &
                descriptor_buffer.descriptorBufferImageLayoutIgnored;
            other_features.vk_physical_device_descriptor_buffer_features_ext
                .descriptorBufferPushDescriptors =
                other_features.vk_physical_device_descriptor_buffer_features_ext
                    .descriptorBufferPushDescriptors &
                descriptor_buffer.descriptorBufferPushDescriptors;
        } else Inner.reset(&other_features.vk_physical_device_descriptor_buffer_features_ext);

        if (find_pnext(
            vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_OBJECT_FEATURES_EXT,
            wf.pNext,
        )) |item| {
            const shader_object: *const vk.VkPhysicalDeviceShaderObjectFeaturesEXT =
                @ptrCast(@alignCast(item));
            other_features.vk_physical_device_shader_object_features_ext.shaderObject =
                other_features.vk_physical_device_shader_object_features_ext.shaderObject &
                shader_object.shaderObject;
        } else Inner.reset(&other_features.vk_physical_device_shader_object_features_ext);

        if (find_pnext(
            vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PRIMITIVES_GENERATED_QUERY_FEATURES_EXT,
            wf.pNext,
        )) |item| {
            const prim_generated: *const vk.VkPhysicalDevicePrimitivesGeneratedQueryFeaturesEXT =
                @ptrCast(@alignCast(item));
            other_features.vk_physical_device_primitives_generated_query_features_ext
                .primitivesGeneratedQuery =
                other_features.vk_physical_device_primitives_generated_query_features_ext
                    .primitivesGeneratedQuery &
                prim_generated.primitivesGeneratedQuery;

            other_features.vk_physical_device_primitives_generated_query_features_ext
                .primitivesGeneratedQueryWithNonZeroStreams =
                other_features.vk_physical_device_primitives_generated_query_features_ext
                    .primitivesGeneratedQueryWithNonZeroStreams &
                prim_generated.primitivesGeneratedQueryWithNonZeroStreams;

            other_features.vk_physical_device_primitives_generated_query_features_ext
                .primitivesGeneratedQueryWithRasterizerDiscard =
                other_features.vk_physical_device_primitives_generated_query_features_ext
                    .primitivesGeneratedQueryWithRasterizerDiscard &
                prim_generated.primitivesGeneratedQueryWithRasterizerDiscard;
        } else Inner.reset(&other_features.vk_physical_device_primitives_generated_query_features_ext);

        if (find_pnext(
            vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_2D_VIEW_OF_3D_FEATURES_EXT,
            wf.pNext,
        )) |item| {
            const image_2d_view_of_3d: *const vk.VkPhysicalDeviceImage2DViewOf3DFeaturesEXT =
                @ptrCast(@alignCast(item));
            other_features.vk_physical_device_image_2d_view_of_3d_features_ext.image2DViewOf3D =
                other_features.vk_physical_device_image_2d_view_of_3d_features_ext
                    .image2DViewOf3D &
                image_2d_view_of_3d.image2DViewOf3D;

            other_features.vk_physical_device_image_2d_view_of_3d_features_ext.sampler2DViewOf3D =
                other_features.vk_physical_device_image_2d_view_of_3d_features_ext
                    .sampler2DViewOf3D &
                image_2d_view_of_3d.sampler2DViewOf3D;
        } else {
            Inner.reset(&other_features.vk_physical_device_image_2d_view_of_3d_features_ext);
        }
    } else {
        current_features.features.robustBufferAccess = vk.VK_FALSE;
        Inner.reset(&other_features.vk_physical_device_robustness_2_features_ext);
        Inner.reset(&other_features.vk_physical_device_image_robustness_features_ext);
        Inner.reset(&other_features.vk_physical_device_fragment_shading_rate_enums_features_nv);
        Inner.reset(&other_features.vk_physical_device_fragment_shading_rate_features_khr);
        Inner.reset(&other_features.vk_physical_device_mesh_shader_features_ext);
        Inner.reset(&other_features.vk_physical_device_mesh_shader_features_nv);
        Inner.reset(&other_features.vk_physical_device_descriptor_buffer_features_ext);
        Inner.reset(&other_features.vk_physical_device_shader_object_features_ext);
        Inner.reset(&other_features.vk_physical_device_primitives_generated_query_features_ext);
        Inner.reset(&other_features.vk_physical_device_image_2d_view_of_3d_features_ext);
    }
}

fn filter_active_extensions(
    current_features: *vk.VkPhysicalDeviceFeatures2,
    all_extenson_names: [][*c]const u8,
) [][*c]const u8 {
    const Inner = struct {
        fn remove_from_slice(slice: [][*c]const u8, value: [:0]const u8) [][*c]const u8 {
            for (slice, 0..) |name, i| {
                const n: [:0]const u8 = std.mem.span(name);
                if (std.mem.eql(u8, n, value)) {
                    slice[i] = slice[slice.len - 1];
                    return slice[0 .. slice.len - 1];
                }
            }
            return slice;
        }
    };
    var current_pnext: ?*const vk.VkBaseInStructure =
        @ptrCast(@alignCast(current_features.pNext));
    current_features.pNext = null;
    var last_pnext: *?*anyopaque = &current_features.pNext;
    var result: [][*c]const u8 = all_extenson_names;
    while (current_pnext) |current| {
        current_pnext = current.pNext;
        var accept: bool = true;

        switch (current.sType) {
            vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_ENUMS_FEATURES_NV => {
                const feature: *const vk.VkPhysicalDeviceFragmentShadingRateEnumsFeaturesNV =
                    @ptrCast(@alignCast(current));
                if (feature.fragmentShadingRateEnums == vk.VK_FALSE and
                    feature.noInvocationFragmentShadingRates == vk.VK_FALSE and
                    feature.supersampleFragmentShadingRates == vk.VK_FALSE)
                {
                    log.debug(
                        @src(),
                        "Filtering out VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_ENUMS_FEATURES_NV from device extensions",
                        .{},
                    );
                    result = Inner.remove_from_slice(
                        result,
                        vk.VK_NV_FRAGMENT_SHADING_RATE_ENUMS_EXTENSION_NAME,
                    );
                    accept = false;
                }
            },
            vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_FEATURES_KHR => {
                const feature: *const vk.VkPhysicalDeviceFragmentShadingRateFeaturesKHR =
                    @ptrCast(@alignCast(current));
                if (feature.attachmentFragmentShadingRate == vk.VK_FALSE and
                    feature.pipelineFragmentShadingRate == vk.VK_FALSE and
                    feature.primitiveFragmentShadingRate == vk.VK_FALSE)
                {
                    log.debug(
                        @src(),
                        "Filtering out VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_FEATURES_KHR from device extensions",
                        .{},
                    );
                    result = Inner.remove_from_slice(
                        result,
                        vk.VK_KHR_FRAGMENT_SHADING_RATE_EXTENSION_NAME,
                    );
                    accept = false;
                }
            },
            vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT => {
                const feature: *const vk.VkPhysicalDeviceRobustness2FeaturesEXT =
                    @ptrCast(@alignCast(current));
                if (feature.nullDescriptor == vk.VK_FALSE and
                    feature.robustBufferAccess2 == vk.VK_FALSE and
                    feature.robustImageAccess2 == vk.VK_FALSE)
                {
                    log.debug(
                        @src(),
                        "Filtering out VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT  from device extensions",
                        .{},
                    );
                    result = Inner.remove_from_slice(
                        result,
                        vk.VK_EXT_ROBUSTNESS_2_EXTENSION_NAME,
                    );
                    accept = false;
                }
            },
            vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_ROBUSTNESS_FEATURES_EXT => {
                const feature: *const vk.VkPhysicalDeviceImageRobustnessFeaturesEXT =
                    @ptrCast(@alignCast(current));
                if (feature.robustImageAccess == vk.VK_FALSE) {
                    log.debug(
                        @src(),
                        "Filtering out VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_ROBUSTNESS_FEATURES_EXT  from device extensions",
                        .{},
                    );
                    result = Inner.remove_from_slice(
                        result,
                        vk.VK_EXT_IMAGE_ROBUSTNESS_EXTENSION_NAME,
                    );
                    accept = false;
                }
            },
            vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_EXT => {
                const feature: *const vk.VkPhysicalDeviceMeshShaderFeaturesEXT =
                    @ptrCast(@alignCast(current));
                if (feature.meshShader == vk.VK_FALSE and
                    feature.taskShader == vk.VK_FALSE and
                    feature.multiviewMeshShader == vk.VK_FALSE and
                    feature.primitiveFragmentShadingRateMeshShader == vk.VK_FALSE and
                    feature.meshShaderQueries == vk.VK_FALSE)
                {
                    log.debug(
                        @src(),
                        "Filtering out VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_EXT  from device extensions",
                        .{},
                    );
                    result = Inner.remove_from_slice(
                        result,
                        vk.VK_EXT_MESH_SHADER_EXTENSION_NAME,
                    );
                    accept = false;
                }
            },
            vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_NV => {
                const feature: *const vk.VkPhysicalDeviceMeshShaderFeaturesNV =
                    @ptrCast(@alignCast(current));
                if (feature.meshShader == vk.VK_FALSE and
                    feature.taskShader == vk.VK_FALSE)
                {
                    log.debug(
                        @src(),
                        "Filtering out VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_NV from device extensions",
                        .{},
                    );
                    result = Inner.remove_from_slice(result, vk.VK_NV_MESH_SHADER_EXTENSION_NAME);
                    accept = false;
                }
            },
            vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_FEATURES_EXT => {
                const feature: *const vk.VkPhysicalDeviceDescriptorBufferFeaturesEXT =
                    @ptrCast(@alignCast(current));
                if (feature.descriptorBuffer == vk.VK_FALSE and
                    feature.descriptorBufferCaptureReplay == vk.VK_FALSE and
                    feature.descriptorBufferImageLayoutIgnored == vk.VK_FALSE and
                    feature.descriptorBufferPushDescriptors == vk.VK_FALSE)
                {
                    log.debug(
                        @src(),
                        "Filtering out VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_FEATURES_EXT from device extensions",
                        .{},
                    );
                    result = Inner.remove_from_slice(
                        result,
                        vk.VK_EXT_DESCRIPTOR_BUFFER_EXTENSION_NAME,
                    );
                    accept = false;
                }
            },
            vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_OBJECT_FEATURES_EXT => {
                const feature: *const vk.VkPhysicalDeviceShaderObjectFeaturesEXT =
                    @ptrCast(@alignCast(current));
                if (feature.shaderObject == vk.VK_FALSE) {
                    log.debug(
                        @src(),
                        "Filtering out VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_OBJECT_FEATURES_EXT from device extensions",
                        .{},
                    );
                    result = Inner.remove_from_slice(
                        result,
                        vk.VK_EXT_SHADER_OBJECT_EXTENSION_NAME,
                    );
                    accept = false;
                }
            },
            vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PRIMITIVES_GENERATED_QUERY_FEATURES_EXT => {
                const feature: *const vk.VkPhysicalDevicePrimitivesGeneratedQueryFeaturesEXT =
                    @ptrCast(@alignCast(current));
                if (feature.primitivesGeneratedQuery == vk.VK_FALSE and
                    feature.primitivesGeneratedQueryWithNonZeroStreams == vk.VK_FALSE and
                    feature.primitivesGeneratedQueryWithRasterizerDiscard == vk.VK_FALSE)
                {
                    log.debug(
                        @src(),
                        "Filtering out VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PRIMITIVES_GENERATED_QUERY_FEATURES_EXT from device extensions",
                        .{},
                    );
                    result = Inner.remove_from_slice(
                        result,
                        vk.VK_EXT_PRIMITIVES_GENERATED_QUERY_EXTENSION_NAME,
                    );
                    accept = false;
                }
            },
            vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_2D_VIEW_OF_3D_FEATURES_EXT => {
                const feature: *const vk.VkPhysicalDeviceImage2DViewOf3DFeaturesEXT =
                    @ptrCast(@alignCast(current));
                if (feature.image2DViewOf3D == vk.VK_FALSE and
                    feature.sampler2DViewOf3D == vk.VK_FALSE)
                {
                    log.debug(
                        @src(),
                        "Filtering out VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_2D_VIEW_OF_3D_FEATURES_EXT from device extensions",
                        .{},
                    );
                    result = Inner.remove_from_slice(
                        result,
                        vk.VK_EXT_IMAGE_2D_VIEW_OF_3D_EXTENSION_NAME,
                    );
                    accept = false;
                }
            },
            else => {},
        }

        if (accept) {
            last_pnext.* = @ptrCast(@constCast(current));
            last_pnext = @ptrCast(@constCast(&current.pNext));
            last_pnext.* = null;
        }
    }
    return result;
}

pub const Device = struct {
    device: vk.VkDevice,
    all_extension_names: []const [*c]const u8,
};
pub fn create_vk_device(
    arena_alloc: Allocator,
    instance: *const Instance,
    physical_device: *const PhysicalDevice,
    application_create_info: *const vk.VkApplicationInfo,
    wanted_physical_device_features2: ?*const vk.VkPhysicalDeviceFeatures2,
    enable_validation: bool,
) !Device {
    const queue_priority: f32 = 1.0;
    const queue_create_info = vk.VkDeviceQueueCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = physical_device.graphics_queue_family,
        .queueCount = 1,
        .pQueuePriorities = &queue_priority,
    };

    // All extensions will be activated for the device. If it
    // supports validation caching, enable it's extension as well.
    const extensions =
        try get_physical_device_exensions(arena_alloc, physical_device.device, null);
    var all_extensions_len = extensions.len;
    if (physical_device.has_validation_cache)
        all_extensions_len += 1;
    var all_extension_names = try arena_alloc.alloc([*c]const u8, all_extensions_len);
    all_extensions_len = 0;
    for (extensions) |*e| {
        var enabled: []const u8 = "enabled";
        if (usable_device_extension(&e.extensionName, extensions, instance.api_version)) {
            all_extension_names[all_extensions_len] = &e.extensionName;
            all_extensions_len += 1;
        } else enabled = "filtered";
        log.debug(@src(), "(PhysicalDevice)({s:^8}) Extension version: {d}.{d}.{d} Name: {s}", .{
            enabled,
            vk.VK_API_VERSION_MAJOR(e.specVersion),
            vk.VK_API_VERSION_MINOR(e.specVersion),
            vk.VK_API_VERSION_PATCH(e.specVersion),
            e.extensionName,
        });
    }
    if (physical_device.has_validation_cache) {
        all_extension_names[all_extensions_len] = vk.VK_EXT_VALIDATION_CACHE_EXTENSION_NAME;
        all_extensions_len += 1;
    }
    all_extension_names = all_extension_names[0..all_extensions_len];

    var physical_device_features_2 = vk.VkPhysicalDeviceFeatures2{
        .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
    };
    var stats: vk.VkPhysicalDevicePipelineExecutablePropertiesFeaturesKHR = .{
        .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PIPELINE_EXECUTABLE_PROPERTIES_FEATURES_KHR,
    };
    physical_device_features_2.pNext = &stats;
    var other_device_features: PDF = .{};
    if (instance.has_properties_2) {
        stats.pNext = other_device_features.chain_supported(all_extension_names);
        vk.vkGetPhysicalDeviceFeatures2KHR.?(physical_device.device, &physical_device_features_2);
    } else vk.vkGetPhysicalDeviceFeatures.?(physical_device.device, &physical_device_features_2.features);

    // Workaround for older dxvk/vkd3d databases, where robustness2 or VRS was not captured,
    // but we expect them to be present. New databases will capture robustness2.
    var wpdf2: ?*const vk.VkPhysicalDeviceFeatures2 = wanted_physical_device_features2;
    var updf2: vk.VkPhysicalDeviceFeatures2 = undefined;
    var spare_robustness2: vk.VkPhysicalDeviceRobustness2FeaturesEXT = undefined;
    var replacement_fragment_shading_rate: vk.VkPhysicalDeviceFragmentShadingRateFeaturesKHR =
        undefined;
    if (wanted_physical_device_features2) |df2| {
        const engine_name: []const u8 = std.mem.span(application_create_info.pEngineName);

        updf2 = df2.*;
        wpdf2 = &updf2;

        if ((std.mem.eql(u8, engine_name, "DXVK") or std.mem.eql(u8, engine_name, "vkd3d")) and
            find_pnext(
                vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_KHR,
                @ptrCast(df2.pNext),
            ) == null)
        {
            spare_robustness2 = .{
                .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT,
                .pNext = updf2.pNext,
                .robustBufferAccess2 = df2.features.robustBufferAccess,
                .robustImageAccess2 = df2.features.robustBufferAccess,
                .nullDescriptor = vk.VK_FALSE,
            };
            updf2.pNext = &spare_robustness2;
        }

        if (std.mem.eql(u8, engine_name, "vkd3d") and
            find_pnext(
                vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_FEATURES_KHR,
                @ptrCast(df2.pNext),
            ) == null)
        {
            replacement_fragment_shading_rate = .{
                .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_FEATURES_KHR,
                .pNext = updf2.pNext,
                .pipelineFragmentShadingRate = vk.VK_TRUE,
                .primitiveFragmentShadingRate = vk.VK_TRUE,
                .attachmentFragmentShadingRate = vk.VK_TRUE,
            };
            updf2.pNext = &replacement_fragment_shading_rate;
        }
    }

    filter_features(&physical_device_features_2, &other_device_features, wpdf2);
    all_extension_names = filter_active_extensions(
        &physical_device_features_2,
        all_extension_names,
    );

    const enabled_layers = if (enable_validation) &VK_VALIDATION_LAYERS_NAMES else &.{};

    const create_info = vk.VkDeviceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pQueueCreateInfos = &queue_create_info,
        .queueCreateInfoCount = 1,
        .ppEnabledLayerNames = @ptrCast(enabled_layers.ptr),
        .enabledLayerCount = @as(u32, @intCast(enabled_layers.len)),
        .ppEnabledExtensionNames = all_extension_names.ptr,
        .enabledExtensionCount = @as(u32, @intCast(all_extension_names.len)),
        .pEnabledFeatures = if (instance.has_properties_2)
            null
        else
            &physical_device_features_2.features,
        .pNext = if (instance.has_properties_2) &physical_device_features_2 else null,
    };

    var vk_device: vk.VkDevice = undefined;
    try vv.check_result(vk.vkCreateDevice.?(
        physical_device.device,
        &create_info,
        null,
        &vk_device,
    ));
    return .{
        .device = vk_device,
        .all_extension_names = all_extension_names,
    };
}

pub fn create_vk_sampler(
    vk_device: vk.VkDevice,
    create_info: *const vk.VkSamplerCreateInfo,
) !vk.VkSampler {
    var sampler: vk.VkSampler = undefined;
    try vv.check_result(vk.vkCreateSampler.?(
        vk_device,
        create_info,
        null,
        &sampler,
    ));
    return sampler;
}

pub fn destroy_vk_sampler(
    vk_device: vk.VkDevice,
    sampler: vk.VkSampler,
) void {
    vk.vkDestroySampler.?(vk_device, sampler, null);
}

pub fn create_descriptor_set_layout(
    vk_device: vk.VkDevice,
    create_info: *const vk.VkDescriptorSetLayoutCreateInfo,
) !vk.VkDescriptorSetLayout {
    var descriptor_set_layout: vk.VkDescriptorSetLayout = undefined;
    try vv.check_result(vk.vkCreateDescriptorSetLayout.?(
        vk_device,
        create_info,
        null,
        &descriptor_set_layout,
    ));
    return descriptor_set_layout;
}

pub fn destroy_descriptor_set_layout(
    vk_device: vk.VkDevice,
    layout: vk.VkDescriptorSetLayout,
) void {
    vk.vkDestroyDescriptorSetLayout.?(vk_device, layout, null);
}

pub fn create_pipeline_layout(
    vk_device: vk.VkDevice,
    create_info: *const vk.VkPipelineLayoutCreateInfo,
) !vk.VkPipelineLayout {
    var pipeline_layout: vk.VkPipelineLayout = undefined;
    try vv.check_result(vk.vkCreatePipelineLayout.?(
        vk_device,
        create_info,
        null,
        &pipeline_layout,
    ));
    return pipeline_layout;
}

pub fn destroy_pipeline_layout(
    vk_device: vk.VkDevice,
    layout: vk.VkPipelineLayout,
) void {
    vk.vkDestroyPipelineLayout.?(vk_device, layout, null);
}

pub fn create_shader_module(
    vk_device: vk.VkDevice,
    create_info: *const vk.VkShaderModuleCreateInfo,
) !vk.VkShaderModule {
    var shader_module: vk.VkShaderModule = undefined;
    try vv.check_result(vk.vkCreateShaderModule.?(
        vk_device,
        create_info,
        null,
        &shader_module,
    ));
    return shader_module;
}

pub fn destroy_shader_module(
    vk_device: vk.VkDevice,
    shader_module: vk.VkShaderModule,
) void {
    vk.vkDestroyShaderModule.?(vk_device, shader_module, null);
}

pub fn create_render_pass(
    vk_device: vk.VkDevice,
    create_info: *align(8) const anyopaque,
) !vk.VkRenderPass {
    const base_type: *const vk.VkBaseInStructure = @ptrCast(create_info);
    var render_pass: vk.VkRenderPass = undefined;
    switch (base_type.sType) {
        vk.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        => try vv.check_result(vk.vkCreateRenderPass.?(
            vk_device,
            @ptrCast(create_info),
            null,
            &render_pass,
        )),
        vk.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO_2,
        => try vv.check_result(vk.vkCreateRenderPass2.?(
            vk_device,
            @ptrCast(create_info),
            null,
            &render_pass,
        )),
        else => return error.InvalidCreateInfoForRenderPass,
    }
    return render_pass;
}

pub fn destroy_render_pass(
    vk_device: vk.VkDevice,
    render_pass: vk.VkRenderPass,
) void {
    vk.vkDestroyRenderPass.?(vk_device, render_pass, null);
}

pub fn create_graphics_pipeline(
    vk_device: vk.VkDevice,
    create_info: *const vk.VkGraphicsPipelineCreateInfo,
) !vk.VkPipeline {
    // vu.print_chain(create_info);
    var pipeline: vk.VkPipeline = undefined;
    try vv.check_result(vk.vkCreateGraphicsPipelines.?(
        vk_device,
        null,
        1,
        create_info,
        null,
        &pipeline,
    ));
    return pipeline;
}

pub fn create_compute_pipeline(
    vk_device: vk.VkDevice,
    create_info: *const vk.VkComputePipelineCreateInfo,
) !vk.VkPipeline {
    var pipeline: vk.VkPipeline = undefined;
    try vv.check_result(vk.vkCreateComputePipelines.?(
        vk_device,
        null,
        1,
        create_info,
        null,
        &pipeline,
    ));
    return pipeline;
}

pub fn create_raytracing_pipeline(
    vk_device: vk.VkDevice,
    create_info: *const vk.VkRayTracingPipelineCreateInfoKHR,
) !vk.VkPipeline {
    var pipeline: vk.VkPipeline = undefined;
    try vv.check_result(vk.vkCreateRayTracingPipelinesKHR.?(
        vk_device,
        null,
        null,
        1,
        create_info,
        null,
        &pipeline,
    ));
    return pipeline;
}

pub fn destroy_pipeline(
    vk_device: vk.VkDevice,
    pipeline: vk.VkPipeline,
) void {
    vk.vkDestroyPipeline.?(vk_device, pipeline, null);
}
