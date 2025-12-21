// Copyright (c) 2025 Egor Lazarchuk
//
// Based in part on Fossilize project which is:
// Copyright (c) 2025 Hans-Kristian Arntzen
//
// SPDX-License-Identifier: MIT

const std = @import("std");
const a = @import("spirv");
const log = @import("log.zig");
const parsing = @import("parsing.zig");
const profiler = @import("profiler.zig");
const vv = @import("vulkan_validation.zig");
const volk = @import("volk");
const vulkan = @import("vulkan.zig");

const Allocator = std.mem.Allocator;
const Database = @import("database.zig");

pub const MEASUREMENTS = profiler.Measurements(
    "vulkan",
    profiler.all_function_names_in_struct(@This()),
);

pub fn init(
    arena_alloc: Allocator,
    tmp_alloc: Allocator,
    db: *const Database,
    enable_vulkan_validation_layers: bool,
    validation: *vv.Validation,
) !volk.VkDevice {
    const app_infos = db.entries.getPtrConst(.application_info).values();
    if (app_infos.len == 0)
        return error.NoApplicationInfoInTheDatabase;
    const app_info_entry = &app_infos[0];
    const app_info_payload = try app_info_entry.get_payload(arena_alloc, tmp_alloc, db);
    const parsed_application_info = try parsing.parse_application_info(
        arena_alloc,
        tmp_alloc,
        db,
        app_info_payload,
    );
    if (parsed_application_info.version != 6)
        return error.ApllicationInfoVersionMissmatch;

    try vv.check_result(volk.volkInitialize());
    const instance = try vulkan.create_vk_instance(
        tmp_alloc,
        parsed_application_info.application_info,
        enable_vulkan_validation_layers,
    );
    volk.volkLoadInstance(instance.instance);
    if (enable_vulkan_validation_layers)
        _ = try vulkan.init_debug_callback(instance.instance);

    const physical_device = try vulkan.select_physical_device(
        tmp_alloc,
        instance.instance,
        enable_vulkan_validation_layers,
    );

    const device = try vulkan.create_vk_device(
        tmp_alloc,
        &instance,
        &physical_device,
        parsed_application_info.application_info,
        parsed_application_info.device_features2,
        &validation.pdf,
        &validation.additional_pdf,
        enable_vulkan_validation_layers,
    );
    validation.api_version = instance.api_version;
    validation.extensions = try .init(
        tmp_alloc,
        instance.api_version,
        instance.all_extension_names,
        device.all_extension_names,
    );

    return device.device;
}

const VK_VALIDATION_LAYERS_NAMES = [_][*c]const u8{"VK_LAYER_KHRONOS_validation"};
const VK_ADDITIONAL_EXTENSIONS_NAMES = [_][*c]const u8{"VK_EXT_debug_utils"};

pub fn contains_all_extensions(
    log_prefix: ?[]const u8,
    extensions: []const volk.VkExtensionProperties,
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
                volk.VK_API_VERSION_MAJOR(e.specVersion),
                volk.VK_API_VERSION_MINOR(e.specVersion),
                volk.VK_API_VERSION_PATCH(e.specVersion),
                e.extensionName,
            });
    }
    return found_extensions == to_find.len;
}

pub fn contains_all_layers(
    log_prefix: ?[]const u8,
    layers: []const volk.VkLayerProperties,
    to_find: []const [*c]const u8,
) bool {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

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
                volk.VK_API_VERSION_MAJOR(l.specVersion),
                volk.VK_API_VERSION_MINOR(l.specVersion),
                volk.VK_API_VERSION_PATCH(l.specVersion),
                l.description,
            });
    }
    return found_layers == to_find.len;
}

pub fn get_instance_extensions(arena_alloc: Allocator) ![]const volk.VkExtensionProperties {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    var extensions_count: u32 = 0;
    try vv.check_result(volk.vkEnumerateInstanceExtensionProperties.?(
        null,
        &extensions_count,
        null,
    ));
    const extensions = try arena_alloc.alloc(volk.VkExtensionProperties, extensions_count);
    try vv.check_result(volk.vkEnumerateInstanceExtensionProperties.?(
        null,
        &extensions_count,
        extensions.ptr,
    ));
    return extensions;
}

pub fn get_instance_layer_properties(arena_alloc: Allocator) ![]const volk.VkLayerProperties {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    var layer_property_count: u32 = 0;
    try vv.check_result(volk.vkEnumerateInstanceLayerProperties.?(&layer_property_count, null));
    const layers = try arena_alloc.alloc(volk.VkLayerProperties, layer_property_count);
    try vv.check_result(volk.vkEnumerateInstanceLayerProperties.?(
        &layer_property_count,
        layers.ptr,
    ));
    return layers;
}

pub const Instance = struct {
    instance: volk.VkInstance,
    api_version: u32,
    has_properties_2: bool,
    all_extension_names: []const [*c]const u8,
};
pub fn create_vk_instance(
    arena_alloc: Allocator,
    requested_app_info: ?*const volk.VkApplicationInfo,
    enable_validation: bool,
) !Instance {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    const api_version = volk.volkGetInstanceVersion();
    log.info(
        @src(),
        "Supported vulkan version: {d}.{d}.{d}",
        .{
            volk.VK_API_VERSION_MAJOR(api_version),
            volk.VK_API_VERSION_MINOR(api_version),
            volk.VK_API_VERSION_PATCH(api_version),
        },
    );
    if (requested_app_info) |app_info| {
        log.info(
            @src(),
            "Requested app info vulkan version: {d}.{d}.{d}",
            .{
                volk.VK_API_VERSION_MAJOR(app_info.apiVersion),
                volk.VK_API_VERSION_MINOR(app_info.apiVersion),
                volk.VK_API_VERSION_PATCH(app_info.apiVersion),
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
        &.{volk.VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME},
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
        &volk.VkApplicationInfo{
            .sType = volk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName = "glacier",
            .applicationVersion = volk.VK_MAKE_VERSION(0, 0, 1),
            .pEngineName = "glacier",
            .engineVersion = volk.VK_MAKE_VERSION(0, 0, 1),
            .apiVersion = api_version,
            .pNext = null,
        };
    log.info(@src(), "Creating instance with application name: {s} engine name: {s} api version: {d}.{d}.{d}", .{
        app_info.pApplicationName,
        app_info.pEngineName,
        volk.VK_API_VERSION_MAJOR(app_info.apiVersion),
        volk.VK_API_VERSION_MINOR(app_info.apiVersion),
        volk.VK_API_VERSION_PATCH(app_info.apiVersion),
    });
    const instance_create_info = volk.VkInstanceCreateInfo{
        .sType = volk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = app_info,
        .ppEnabledExtensionNames = all_extension_names.ptr,
        .enabledExtensionCount = @as(u32, @intCast(all_extension_names.len)),
        .ppEnabledLayerNames = @ptrCast(enabled_layers.ptr),
        .enabledLayerCount = @as(u32, @intCast(enabled_layers.len)),
    };

    var vk_instance: volk.VkInstance = undefined;
    try vv.check_result(volk.vkCreateInstance.?(&instance_create_info, null, &vk_instance));
    log.debug(
        @src(),
        "Created instance api version: {d}.{d}.{d} has_properties_2: {}",
        .{
            volk.VK_API_VERSION_MAJOR(api_version),
            volk.VK_API_VERSION_MINOR(api_version),
            volk.VK_API_VERSION_PATCH(api_version),
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

pub fn init_debug_callback(instance: volk.VkInstance) !volk.VkDebugReportCallbackEXT {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    const create_info = volk.VkDebugReportCallbackCreateInfoEXT{
        .sType = volk.VK_STRUCTURE_TYPE_DEBUG_REPORT_CALLBACK_CREATE_INFO_EXT,
        .pfnCallback = debug_callback,
        .flags = volk.VK_DEBUG_REPORT_ERROR_BIT_EXT |
            volk.VK_DEBUG_REPORT_WARNING_BIT_EXT,
        .pUserData = null,
    };

    var callback: volk.VkDebugReportCallbackEXT = undefined;
    try vv.check_result(
        volk.vkCreateDebugReportCallbackEXT.?(
            instance,
            &create_info,
            null,
            &callback,
        ),
    );
    return callback;
}

pub fn debug_callback(
    flags: volk.VkDebugReportFlagsEXT,
    _: volk.VkDebugReportObjectTypeEXT,
    _: u64,
    _: usize,
    _: i32,
    layer: [*c]const u8,
    message: [*c]const u8,
    _: ?*anyopaque,
) callconv(.c) volk.VkBool32 {
    if (flags & volk.VK_DEBUG_REPORT_WARNING_BIT_EXT != 0)
        log.warn(@src(), "Layer: {s} Message: {s}", .{ layer, message });
    if (flags & volk.VK_DEBUG_REPORT_ERROR_BIT_EXT != 0)
        log.err(@src(), "Layer: {s} Message: {s}", .{ layer, message });

    return volk.VK_FALSE;
}

pub fn get_physical_devices(
    arena_alloc: Allocator,
    vk_instance: volk.VkInstance,
) ![]const volk.VkPhysicalDevice {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    var physical_device_count: u32 = 0;
    try vv.check_result(volk.vkEnumeratePhysicalDevices.?(
        vk_instance,
        &physical_device_count,
        null,
    ));
    const physical_devices = try arena_alloc.alloc(
        volk.VkPhysicalDevice,
        physical_device_count,
    );
    try vv.check_result(volk.vkEnumeratePhysicalDevices.?(
        vk_instance,
        &physical_device_count,
        physical_devices.ptr,
    ));
    return physical_devices;
}

pub fn get_physical_device_exensions(
    arena_alloc: Allocator,
    physical_device: volk.VkPhysicalDevice,
    extension_name: [*c]const u8,
) ![]const volk.VkExtensionProperties {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    var extensions_count: u32 = 0;
    try vv.check_result(volk.vkEnumerateDeviceExtensionProperties.?(
        physical_device,
        extension_name,
        &extensions_count,
        null,
    ));
    const extensions = try arena_alloc.alloc(volk.VkExtensionProperties, extensions_count);
    try vv.check_result(volk.vkEnumerateDeviceExtensionProperties.?(
        physical_device,
        extension_name,
        &extensions_count,
        extensions.ptr,
    ));
    return extensions;
}

pub fn get_physical_device_layers(
    arena_alloc: Allocator,
    physical_device: volk.VkPhysicalDevice,
) ![]const volk.VkLayerProperties {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    var layer_property_count: u32 = 0;
    try vv.check_result(volk.vkEnumerateDeviceLayerProperties.?(
        physical_device,
        &layer_property_count,
        null,
    ));
    const layers = try arena_alloc.alloc(volk.VkLayerProperties, layer_property_count);
    try vv.check_result(volk.vkEnumerateDeviceLayerProperties.?(
        physical_device,
        &layer_property_count,
        layers.ptr,
    ));
    return layers;
}

pub const PhysicalDevice = struct {
    device: volk.VkPhysicalDevice,
    graphics_queue_family: u32,
    has_validation_cache: bool,
};

pub fn select_physical_device(
    arena_alloc: Allocator,
    vk_instance: volk.VkInstance,
    enable_validation: bool,
) !PhysicalDevice {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    const physical_devices = try get_physical_devices(arena_alloc, vk_instance);

    for (physical_devices) |physical_device| {
        var properties: volk.VkPhysicalDeviceProperties = undefined;
        volk.vkGetPhysicalDeviceProperties.?(physical_device, &properties);

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
            volk.VK_API_VERSION_MAJOR(properties.apiVersion),
            volk.VK_API_VERSION_MINOR(properties.apiVersion),
            volk.VK_API_VERSION_PATCH(properties.apiVersion),
            volk.VK_API_VERSION_MAJOR(properties.driverVersion),
            volk.VK_API_VERSION_MINOR(properties.driverVersion),
            volk.VK_API_VERSION_PATCH(properties.driverVersion),
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
                &.{volk.VK_EXT_VALIDATION_CACHE_EXTENSION_NAME},
            );
        } else false;

        // Because the exact queue does not matter much,
        // select the first queue with graphics capability.
        var queue_family_count: u32 = 0;
        volk.vkGetPhysicalDeviceQueueFamilyProperties.?(physical_device, &queue_family_count, null);
        const queue_families = try arena_alloc.alloc(
            volk.VkQueueFamilyProperties,
            queue_family_count,
        );
        volk.vkGetPhysicalDeviceQueueFamilyProperties.?(
            physical_device,
            &queue_family_count,
            queue_families.ptr,
        );
        var graphics_queue_family: ?u32 = null;
        for (queue_families, 0..) |qf, i| {
            if (qf.queueFlags & volk.VK_QUEUE_GRAPHICS_BIT != 0) {
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
    all_ext_props: []const volk.VkExtensionProperties,
    api_version: u32,
) bool {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    const e = std.mem.span(ext);
    if (std.mem.eql(u8, e, volk.VK_AMD_NEGATIVE_VIEWPORT_HEIGHT_EXTENSION_NAME))
        // illigal to enable with maintenance1
        return false;
    if (std.mem.eql(u8, e, volk.VK_NV_RAY_TRACING_EXTENSION_NAME))
        // causes problems with pipeline replaying
        return false;
    if (std.mem.eql(u8, e, volk.VK_AMD_SHADER_INFO_EXTENSION_NAME))
        // Mesa disables shader cache when thisi is enabled.
        return false;
    if (std.mem.eql(u8, e, volk.VK_EXT_BUFFER_DEVICE_ADDRESS_EXTENSION_NAME))
        for (all_ext_props) |other_ext| {
            const other_e = std.mem.span(@as([*c]const u8, @ptrCast(&other_ext.extensionName)));
            if (std.mem.eql(u8, other_e, volk.VK_KHR_BUFFER_DEVICE_ADDRESS_EXTENSION_NAME))
                return false;
        };
    if (std.mem.eql(u8, e, volk.VK_AMD_SHADER_FRAGMENT_MASK_EXTENSION_NAME))
        for (all_ext_props) |other_ext| {
            const other_e = std.mem.span(@as([*c]const u8, @ptrCast(&other_ext.extensionName)));
            if (std.mem.eql(u8, other_e, volk.VK_EXT_DESCRIPTOR_BUFFER_EXTENSION_NAME))
                return false;
        };

    const VK_1_1_EXTS: []const []const u8 = &.{
        volk.VK_KHR_SHADER_SUBGROUP_EXTENDED_TYPES_EXTENSION_NAME,
        volk.VK_KHR_SPIRV_1_4_EXTENSION_NAME,
        volk.VK_KHR_SHARED_PRESENTABLE_IMAGE_EXTENSION_NAME,
        volk.VK_KHR_SHADER_FLOAT_CONTROLS_EXTENSION_NAME,
        volk.VK_KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME,
        volk.VK_KHR_RAY_TRACING_PIPELINE_EXTENSION_NAME,
        volk.VK_KHR_RAY_QUERY_EXTENSION_NAME,
        volk.VK_KHR_MAINTENANCE_4_EXTENSION_NAME,
        volk.VK_KHR_SHADER_SUBGROUP_UNIFORM_CONTROL_FLOW_EXTENSION_NAME,
        volk.VK_EXT_SUBGROUP_SIZE_CONTROL_EXTENSION_NAME,
        volk.VK_NV_SHADER_SM_BUILTINS_EXTENSION_NAME,
        volk.VK_NV_SHADER_SUBGROUP_PARTITIONED_EXTENSION_NAME,
        volk.VK_NV_DEVICE_GENERATED_COMMANDS_EXTENSION_NAME,
    };

    var is_vk_1_1_ext: bool = false;
    for (VK_1_1_EXTS) |vk_1_1_ext|
        if (std.mem.eql(u8, vk_1_1_ext, e)) {
            is_vk_1_1_ext = true;
            break;
        };

    if (api_version < volk.VK_API_VERSION_1_1 and is_vk_1_1_ext) {
        return false;
    }

    return true;
}

pub fn find_pnext(stype: u32, item: ?*const anyopaque) ?*anyopaque {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    var pnext: ?*const volk.VkBaseInStructure = @ptrCast(@alignCast(item));
    while (pnext) |next| {
        pnext = next.pNext;
        if (next.sType == stype) return @ptrCast(@constCast(next));
    }
    return null;
}

pub fn filter_features(
    current_pdf: *volk.VkPhysicalDeviceFeatures2,
    additional_pdf: *vv.AdditionalPDF,
    wanted_pdf: ?*const volk.VkPhysicalDeviceFeatures2,
) void {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    const Inner = struct {
        fn reset(item: anytype) void {
            const child = @typeInfo(@TypeOf(item)).pointer.child;
            const type_info = @typeInfo(child).@"struct";
            inline for (type_info.fields) |field| {
                if (field.type == volk.VkBool32) @field(item, field.name) = volk.VK_FALSE;
            }
        }
        fn apply(comptime T: type, item1: *T, item2: *const T) void {
            const type_info = @typeInfo(T).@"struct";
            inline for (type_info.fields) |field| {
                if (field.type == volk.VkBool32) {
                    @field(item1, field.name) =
                        @field(item1, field.name) & @field(item2, field.name);
                }
            }
        }
    };
    // These feature bits conflict according to validation layers.
    if (additional_pdf.VkPhysicalDeviceFragmentShadingRateFeaturesKHR.pipelineFragmentShadingRate == volk.VK_TRUE or
        additional_pdf.VkPhysicalDeviceFragmentShadingRateFeaturesKHR.attachmentFragmentShadingRate == volk.VK_TRUE or
        additional_pdf.VkPhysicalDeviceFragmentShadingRateFeaturesKHR.primitiveFragmentShadingRate == volk.VK_TRUE)
    {
        additional_pdf.VkPhysicalDeviceShadingRateImageFeaturesNV.shadingRateImage = volk.VK_FALSE;
        additional_pdf.VkPhysicalDeviceShadingRateImageFeaturesNV.shadingRateCoarseSampleOrder = volk.VK_FALSE;
        additional_pdf.VkPhysicalDeviceFragmentDensityMapFeaturesEXT.fragmentDensityMap =
            volk.VK_FALSE;
    }

    // Only enable robustness if requested since it affects compilation on most implementations.
    if (wanted_pdf) |wf| {
        current_pdf.features.robustBufferAccess =
            current_pdf.features.robustBufferAccess & wf.features.robustBufferAccess;

        const PATCH_TYPES: []const struct { u32, type, []const u8 } = &.{
            .{
                volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_KHR,
                volk.VkPhysicalDeviceRobustness2FeaturesKHR,
                "VkPhysicalDeviceRobustness2FeaturesKHR",
            },
            .{
                volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_ROBUSTNESS_FEATURES,
                volk.VkPhysicalDeviceImageRobustnessFeatures,
                "VkPhysicalDeviceImageRobustnessFeatures",
            },
            .{
                volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_ENUMS_FEATURES_NV,
                volk.VkPhysicalDeviceFragmentShadingRateEnumsFeaturesNV,
                "VkPhysicalDeviceFragmentShadingRateEnumsFeaturesNV",
            },
            .{
                volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_FEATURES_KHR,
                volk.VkPhysicalDeviceFragmentShadingRateFeaturesKHR,
                "VkPhysicalDeviceFragmentShadingRateFeaturesKHR",
            },
            .{
                volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_EXT,
                volk.VkPhysicalDeviceMeshShaderFeaturesEXT,
                "VkPhysicalDeviceMeshShaderFeaturesEXT",
            },
            .{
                volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_NV,
                volk.VkPhysicalDeviceMeshShaderFeaturesNV,
                "VkPhysicalDeviceMeshShaderFeaturesNV",
            },
            .{
                volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_FEATURES_EXT,
                volk.VkPhysicalDeviceDescriptorBufferFeaturesEXT,
                "VkPhysicalDeviceDescriptorBufferFeaturesEXT",
            },
            .{
                volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_OBJECT_FEATURES_EXT,
                volk.VkPhysicalDeviceShaderObjectFeaturesEXT,
                "VkPhysicalDeviceShaderObjectFeaturesEXT",
            },
            .{
                volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PRIMITIVES_GENERATED_QUERY_FEATURES_EXT,
                volk.VkPhysicalDevicePrimitivesGeneratedQueryFeaturesEXT,
                "VkPhysicalDevicePrimitivesGeneratedQueryFeaturesEXT",
            },
            .{
                volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_2D_VIEW_OF_3D_FEATURES_EXT,
                volk.VkPhysicalDeviceImage2DViewOf3DFeaturesEXT,
                "VkPhysicalDeviceImage2DViewOf3DFeaturesEXT",
            },
        };
        inline for (PATCH_TYPES) |pt| {
            const stype, const T, const field = pt;

            if (find_pnext(
                stype,
                wf.pNext,
            )) |item| {
                const found: *const T = @ptrCast(@alignCast(item));
                Inner.apply(T, &@field(additional_pdf, field), found);
            } else Inner.reset(&@field(additional_pdf, field));
        }
    } else {
        current_pdf.features.robustBufferAccess = volk.VK_FALSE;
        Inner.reset(&additional_pdf.VkPhysicalDeviceRobustness2FeaturesKHR);
        Inner.reset(&additional_pdf.VkPhysicalDeviceImageRobustnessFeatures);
        Inner.reset(&additional_pdf.VkPhysicalDeviceFragmentShadingRateEnumsFeaturesNV);
        Inner.reset(&additional_pdf.VkPhysicalDeviceFragmentShadingRateFeaturesKHR);
        Inner.reset(&additional_pdf.VkPhysicalDeviceMeshShaderFeaturesEXT);
        Inner.reset(&additional_pdf.VkPhysicalDeviceMeshShaderFeaturesNV);
        Inner.reset(&additional_pdf.VkPhysicalDeviceDescriptorBufferFeaturesEXT);
        Inner.reset(&additional_pdf.VkPhysicalDeviceShaderObjectFeaturesEXT);
        Inner.reset(&additional_pdf.VkPhysicalDevicePrimitivesGeneratedQueryFeaturesEXT);
        Inner.reset(&additional_pdf.VkPhysicalDeviceImage2DViewOf3DFeaturesEXT);
    }
}

pub fn filter_active_extensions(
    current_features: *volk.VkPhysicalDeviceFeatures2,
    all_extenson_names: [][*c]const u8,
) [][*c]const u8 {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

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
    var current_pnext: ?*const volk.VkBaseInStructure =
        @ptrCast(@alignCast(current_features.pNext));
    current_features.pNext = null;
    var last_pnext: *?*anyopaque = &current_features.pNext;
    var result: [][*c]const u8 = all_extenson_names;
    while (current_pnext) |current| {
        current_pnext = current.pNext;
        var accept: bool = true;

        switch (current.sType) {
            volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_ENUMS_FEATURES_NV => {
                const feature: *const volk.VkPhysicalDeviceFragmentShadingRateEnumsFeaturesNV =
                    @ptrCast(@alignCast(current));
                if (feature.fragmentShadingRateEnums == volk.VK_FALSE and
                    feature.noInvocationFragmentShadingRates == volk.VK_FALSE and
                    feature.supersampleFragmentShadingRates == volk.VK_FALSE)
                {
                    log.debug(
                        @src(),
                        "Filtering out VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_ENUMS_FEATURES_NV from device extensions",
                        .{},
                    );
                    result = Inner.remove_from_slice(
                        result,
                        volk.VK_NV_FRAGMENT_SHADING_RATE_ENUMS_EXTENSION_NAME,
                    );
                    accept = false;
                }
            },
            volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_FEATURES_KHR => {
                const feature: *const volk.VkPhysicalDeviceFragmentShadingRateFeaturesKHR =
                    @ptrCast(@alignCast(current));
                if (feature.attachmentFragmentShadingRate == volk.VK_FALSE and
                    feature.pipelineFragmentShadingRate == volk.VK_FALSE and
                    feature.primitiveFragmentShadingRate == volk.VK_FALSE)
                {
                    log.debug(
                        @src(),
                        "Filtering out VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_FEATURES_KHR from device extensions",
                        .{},
                    );
                    result = Inner.remove_from_slice(
                        result,
                        volk.VK_KHR_FRAGMENT_SHADING_RATE_EXTENSION_NAME,
                    );
                    accept = false;
                }
            },
            volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT => {
                const feature: *const volk.VkPhysicalDeviceRobustness2FeaturesEXT =
                    @ptrCast(@alignCast(current));
                if (feature.nullDescriptor == volk.VK_FALSE and
                    feature.robustBufferAccess2 == volk.VK_FALSE and
                    feature.robustImageAccess2 == volk.VK_FALSE)
                {
                    log.debug(
                        @src(),
                        "Filtering out VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT  from device extensions",
                        .{},
                    );
                    result = Inner.remove_from_slice(
                        result,
                        volk.VK_EXT_ROBUSTNESS_2_EXTENSION_NAME,
                    );
                    accept = false;
                }
            },
            volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_ROBUSTNESS_FEATURES_EXT => {
                const feature: *const volk.VkPhysicalDeviceImageRobustnessFeaturesEXT =
                    @ptrCast(@alignCast(current));
                if (feature.robustImageAccess == volk.VK_FALSE) {
                    log.debug(
                        @src(),
                        "Filtering out VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_ROBUSTNESS_FEATURES_EXT  from device extensions",
                        .{},
                    );
                    result = Inner.remove_from_slice(
                        result,
                        volk.VK_EXT_IMAGE_ROBUSTNESS_EXTENSION_NAME,
                    );
                    accept = false;
                }
            },
            volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_EXT => {
                const feature: *const volk.VkPhysicalDeviceMeshShaderFeaturesEXT =
                    @ptrCast(@alignCast(current));
                if (feature.meshShader == volk.VK_FALSE and
                    feature.taskShader == volk.VK_FALSE and
                    feature.multiviewMeshShader == volk.VK_FALSE and
                    feature.primitiveFragmentShadingRateMeshShader == volk.VK_FALSE and
                    feature.meshShaderQueries == volk.VK_FALSE)
                {
                    log.debug(
                        @src(),
                        "Filtering out VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_EXT  from device extensions",
                        .{},
                    );
                    result = Inner.remove_from_slice(
                        result,
                        volk.VK_EXT_MESH_SHADER_EXTENSION_NAME,
                    );
                    accept = false;
                }
            },
            volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_NV => {
                const feature: *const volk.VkPhysicalDeviceMeshShaderFeaturesNV =
                    @ptrCast(@alignCast(current));
                if (feature.meshShader == volk.VK_FALSE and
                    feature.taskShader == volk.VK_FALSE)
                {
                    log.debug(
                        @src(),
                        "Filtering out VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_NV from device extensions",
                        .{},
                    );
                    result = Inner.remove_from_slice(result, volk.VK_NV_MESH_SHADER_EXTENSION_NAME);
                    accept = false;
                }
            },
            volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_FEATURES_EXT => {
                const feature: *const volk.VkPhysicalDeviceDescriptorBufferFeaturesEXT =
                    @ptrCast(@alignCast(current));
                if (feature.descriptorBuffer == volk.VK_FALSE and
                    feature.descriptorBufferCaptureReplay == volk.VK_FALSE and
                    feature.descriptorBufferImageLayoutIgnored == volk.VK_FALSE and
                    feature.descriptorBufferPushDescriptors == volk.VK_FALSE)
                {
                    log.debug(
                        @src(),
                        "Filtering out VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_FEATURES_EXT from device extensions",
                        .{},
                    );
                    result = Inner.remove_from_slice(
                        result,
                        volk.VK_EXT_DESCRIPTOR_BUFFER_EXTENSION_NAME,
                    );
                    accept = false;
                }
            },
            volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_OBJECT_FEATURES_EXT => {
                const feature: *const volk.VkPhysicalDeviceShaderObjectFeaturesEXT =
                    @ptrCast(@alignCast(current));
                if (feature.shaderObject == volk.VK_FALSE) {
                    log.debug(
                        @src(),
                        "Filtering out VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_OBJECT_FEATURES_EXT from device extensions",
                        .{},
                    );
                    result = Inner.remove_from_slice(
                        result,
                        volk.VK_EXT_SHADER_OBJECT_EXTENSION_NAME,
                    );
                    accept = false;
                }
            },
            volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PRIMITIVES_GENERATED_QUERY_FEATURES_EXT => {
                const feature: *const volk.VkPhysicalDevicePrimitivesGeneratedQueryFeaturesEXT =
                    @ptrCast(@alignCast(current));
                if (feature.primitivesGeneratedQuery == volk.VK_FALSE and
                    feature.primitivesGeneratedQueryWithNonZeroStreams == volk.VK_FALSE and
                    feature.primitivesGeneratedQueryWithRasterizerDiscard == volk.VK_FALSE)
                {
                    log.debug(
                        @src(),
                        "Filtering out VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PRIMITIVES_GENERATED_QUERY_FEATURES_EXT from device extensions",
                        .{},
                    );
                    result = Inner.remove_from_slice(
                        result,
                        volk.VK_EXT_PRIMITIVES_GENERATED_QUERY_EXTENSION_NAME,
                    );
                    accept = false;
                }
            },
            volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_2D_VIEW_OF_3D_FEATURES_EXT => {
                const feature: *const volk.VkPhysicalDeviceImage2DViewOf3DFeaturesEXT =
                    @ptrCast(@alignCast(current));
                if (feature.image2DViewOf3D == volk.VK_FALSE and
                    feature.sampler2DViewOf3D == volk.VK_FALSE)
                {
                    log.debug(
                        @src(),
                        "Filtering out VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_2D_VIEW_OF_3D_FEATURES_EXT from device extensions",
                        .{},
                    );
                    result = Inner.remove_from_slice(
                        result,
                        volk.VK_EXT_IMAGE_2D_VIEW_OF_3D_EXTENSION_NAME,
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
    device: volk.VkDevice,
    all_extension_names: []const [*c]const u8,
};
pub fn create_vk_device(
    arena_alloc: Allocator,
    instance: *const Instance,
    physical_device: *const PhysicalDevice,
    application_create_info: *const volk.VkApplicationInfo,
    wanted_physical_device_features2: ?*const volk.VkPhysicalDeviceFeatures2,
    pdf: *volk.VkPhysicalDeviceFeatures2,
    additional_pdf: *vv.AdditionalPDF,
    enable_validation: bool,
) !Device {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    const queue_priority: f32 = 1.0;
    const queue_create_info = volk.VkDeviceQueueCreateInfo{
        .sType = volk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
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
            volk.VK_API_VERSION_MAJOR(e.specVersion),
            volk.VK_API_VERSION_MINOR(e.specVersion),
            volk.VK_API_VERSION_PATCH(e.specVersion),
            e.extensionName,
        });
    }
    if (physical_device.has_validation_cache) {
        all_extension_names[all_extensions_len] = volk.VK_EXT_VALIDATION_CACHE_EXTENSION_NAME;
        all_extensions_len += 1;
    }
    all_extension_names = all_extension_names[0..all_extensions_len];

    pdf.* = volk.VkPhysicalDeviceFeatures2{
        .sType = volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
    };
    var stats: volk.VkPhysicalDevicePipelineExecutablePropertiesFeaturesKHR = .{
        .sType = volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PIPELINE_EXECUTABLE_PROPERTIES_FEATURES_KHR,
    };
    pdf.pNext = &stats;
    if (instance.has_properties_2) {
        stats.pNext = additional_pdf.chain_supported(all_extension_names);
        volk.vkGetPhysicalDeviceFeatures2KHR.?(physical_device.device, pdf);
    } else volk.vkGetPhysicalDeviceFeatures.?(physical_device.device, &pdf.features);

    // Workaround for older dxvk/vkd3d databases, where robustness2 or VRS was not captured,
    // but we expect them to be present. New databases will capture robustness2.
    var wpdf2: ?*const volk.VkPhysicalDeviceFeatures2 = wanted_physical_device_features2;
    var updf2: volk.VkPhysicalDeviceFeatures2 = undefined;
    var spare_robustness2: volk.VkPhysicalDeviceRobustness2FeaturesEXT = undefined;
    var replacement_fragment_shading_rate: volk.VkPhysicalDeviceFragmentShadingRateFeaturesKHR =
        undefined;
    if (wanted_physical_device_features2) |df2| {
        const engine_name: []const u8 = std.mem.span(application_create_info.pEngineName);

        updf2 = df2.*;
        wpdf2 = &updf2;

        if ((std.mem.eql(u8, engine_name, "DXVK") or std.mem.eql(u8, engine_name, "vkd3d")) and
            find_pnext(
                volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_KHR,
                @ptrCast(df2.pNext),
            ) == null)
        {
            spare_robustness2 = .{
                .sType = volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT,
                .pNext = updf2.pNext,
                .robustBufferAccess2 = df2.features.robustBufferAccess,
                .robustImageAccess2 = df2.features.robustBufferAccess,
                .nullDescriptor = volk.VK_FALSE,
            };
            updf2.pNext = &spare_robustness2;
        }

        if (std.mem.eql(u8, engine_name, "vkd3d") and
            find_pnext(
                volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_FEATURES_KHR,
                @ptrCast(df2.pNext),
            ) == null)
        {
            replacement_fragment_shading_rate = .{
                .sType = volk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_FEATURES_KHR,
                .pNext = updf2.pNext,
                .pipelineFragmentShadingRate = volk.VK_TRUE,
                .primitiveFragmentShadingRate = volk.VK_TRUE,
                .attachmentFragmentShadingRate = volk.VK_TRUE,
            };
            updf2.pNext = &replacement_fragment_shading_rate;
        }
    }

    filter_features(pdf, additional_pdf, wpdf2);
    all_extension_names = filter_active_extensions(
        pdf,
        all_extension_names,
    );

    const enabled_layers = if (enable_validation) &VK_VALIDATION_LAYERS_NAMES else &.{};

    const create_info = volk.VkDeviceCreateInfo{
        .sType = volk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pQueueCreateInfos = &queue_create_info,
        .queueCreateInfoCount = 1,
        .ppEnabledLayerNames = @ptrCast(enabled_layers.ptr),
        .enabledLayerCount = @as(u32, @intCast(enabled_layers.len)),
        .ppEnabledExtensionNames = all_extension_names.ptr,
        .enabledExtensionCount = @as(u32, @intCast(all_extension_names.len)),
        .pEnabledFeatures = if (instance.has_properties_2)
            null
        else
            &pdf.features,
        .pNext = if (instance.has_properties_2) pdf else null,
    };

    var vk_device: volk.VkDevice = undefined;
    try vv.check_result(volk.vkCreateDevice.?(
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
    vk_device: volk.VkDevice,
    create_info: *const volk.VkSamplerCreateInfo,
) !volk.VkSampler {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    var sampler: volk.VkSampler = undefined;
    try vv.check_result(volk.vkCreateSampler.?(
        vk_device,
        create_info,
        null,
        &sampler,
    ));
    return sampler;
}

pub fn destroy_vk_sampler(
    vk_device: volk.VkDevice,
    sampler: volk.VkSampler,
) void {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    volk.vkDestroySampler.?(vk_device, sampler, null);
}

pub fn create_descriptor_set_layout(
    vk_device: volk.VkDevice,
    create_info: *const volk.VkDescriptorSetLayoutCreateInfo,
) !volk.VkDescriptorSetLayout {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    var descriptor_set_layout: volk.VkDescriptorSetLayout = undefined;
    try vv.check_result(volk.vkCreateDescriptorSetLayout.?(
        vk_device,
        create_info,
        null,
        &descriptor_set_layout,
    ));
    return descriptor_set_layout;
}

pub fn destroy_descriptor_set_layout(
    vk_device: volk.VkDevice,
    layout: volk.VkDescriptorSetLayout,
) void {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    volk.vkDestroyDescriptorSetLayout.?(vk_device, layout, null);
}

pub fn create_pipeline_layout(
    vk_device: volk.VkDevice,
    create_info: *const volk.VkPipelineLayoutCreateInfo,
) !volk.VkPipelineLayout {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    var pipeline_layout: volk.VkPipelineLayout = undefined;
    try vv.check_result(volk.vkCreatePipelineLayout.?(
        vk_device,
        create_info,
        null,
        &pipeline_layout,
    ));
    return pipeline_layout;
}

pub fn destroy_pipeline_layout(
    vk_device: volk.VkDevice,
    layout: volk.VkPipelineLayout,
) void {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    volk.vkDestroyPipelineLayout.?(vk_device, layout, null);
}

pub fn create_shader_module(
    vk_device: volk.VkDevice,
    create_info: *const volk.VkShaderModuleCreateInfo,
) !volk.VkShaderModule {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    var shader_module: volk.VkShaderModule = undefined;
    try vv.check_result(volk.vkCreateShaderModule.?(
        vk_device,
        create_info,
        null,
        &shader_module,
    ));
    return shader_module;
}

pub fn destroy_shader_module(
    vk_device: volk.VkDevice,
    shader_module: volk.VkShaderModule,
) void {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    volk.vkDestroyShaderModule.?(vk_device, shader_module, null);
}

pub fn create_render_pass(
    vk_device: volk.VkDevice,
    create_info: *align(8) const anyopaque,
) !volk.VkRenderPass {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    const base_type: *const volk.VkBaseInStructure = @ptrCast(create_info);
    var render_pass: volk.VkRenderPass = undefined;
    switch (base_type.sType) {
        volk.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        => try vv.check_result(volk.vkCreateRenderPass.?(
            vk_device,
            @ptrCast(create_info),
            null,
            &render_pass,
        )),
        volk.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO_2,
        => try vv.check_result(volk.vkCreateRenderPass2.?(
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
    vk_device: volk.VkDevice,
    render_pass: volk.VkRenderPass,
) void {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    volk.vkDestroyRenderPass.?(vk_device, render_pass, null);
}

pub fn create_graphics_pipeline(
    vk_device: volk.VkDevice,
    create_info: *const volk.VkGraphicsPipelineCreateInfo,
) !volk.VkPipeline {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    var pipeline: volk.VkPipeline = undefined;
    try vv.check_result(volk.vkCreateGraphicsPipelines.?(
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
    vk_device: volk.VkDevice,
    create_info: *const volk.VkComputePipelineCreateInfo,
) !volk.VkPipeline {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    var pipeline: volk.VkPipeline = undefined;
    try vv.check_result(volk.vkCreateComputePipelines.?(
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
    vk_device: volk.VkDevice,
    create_info: *const volk.VkRayTracingPipelineCreateInfoKHR,
) !volk.VkPipeline {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    var pipeline: volk.VkPipeline = undefined;
    try vv.check_result(volk.vkCreateRayTracingPipelinesKHR.?(
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
    vk_device: volk.VkDevice,
    pipeline: volk.VkPipeline,
) void {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    volk.vkDestroyPipeline.?(vk_device, pipeline, null);
}
