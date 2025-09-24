const std = @import("std");
const vk = @import("volk");
const log = @import("log.zig");
const vu = @import("vulkan_utils.zig");
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
    try vu.check_result(vk.vkEnumerateInstanceExtensionProperties.?(
        null,
        &extensions_count,
        null,
    ));
    const extensions = try arena_alloc.alloc(vk.VkExtensionProperties, extensions_count);
    try vu.check_result(vk.vkEnumerateInstanceExtensionProperties.?(
        null,
        &extensions_count,
        extensions.ptr,
    ));
    return extensions;
}

pub fn get_instance_layer_properties(arena_alloc: Allocator) ![]const vk.VkLayerProperties {
    var layer_property_count: u32 = 0;
    try vu.check_result(vk.vkEnumerateInstanceLayerProperties.?(&layer_property_count, null));
    const layers = try arena_alloc.alloc(vk.VkLayerProperties, layer_property_count);
    try vu.check_result(vk.vkEnumerateInstanceLayerProperties.?(
        &layer_property_count,
        layers.ptr,
    ));
    return layers;
}

pub const Instance = struct {
    instance: vk.VkInstance,
    api_version: u32,
    has_properties_2: bool,
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
    try vu.check_result(vk.vkCreateInstance.?(&instance_create_info, null, &vk_instance));
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
    try vu.check_result(
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
    try vu.check_result(vk.vkEnumeratePhysicalDevices.?(
        vk_instance,
        &physical_device_count,
        null,
    ));
    const physical_devices = try arena_alloc.alloc(
        vk.VkPhysicalDevice,
        physical_device_count,
    );
    try vu.check_result(vk.vkEnumeratePhysicalDevices.?(
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
    try vu.check_result(vk.vkEnumerateDeviceExtensionProperties.?(
        physical_device,
        extension_name,
        &extensions_count,
        null,
    ));
    const extensions = try arena_alloc.alloc(vk.VkExtensionProperties, extensions_count);
    try vu.check_result(vk.vkEnumerateDeviceExtensionProperties.?(
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
    try vu.check_result(vk.vkEnumerateDeviceLayerProperties.?(
        physical_device,
        &layer_property_count,
        null,
    ));
    const layers = try arena_alloc.alloc(vk.VkLayerProperties, layer_property_count);
    try vu.check_result(vk.vkEnumerateDeviceLayerProperties.?(
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
        return false;
    if (std.mem.eql(u8, e, vk.VK_NV_RAY_TRACING_EXTENSION_NAME))
        return false;
    if (std.mem.eql(u8, e, vk.VK_AMD_SHADER_INFO_EXTENSION_NAME))
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

pub fn create_vk_device(
    arena_alloc: Allocator,
    instance: *const Instance,
    physical_device: *const PhysicalDevice,
    device_features2: ?*const vk.VkPhysicalDeviceFeatures2,
    enable_validation: bool,
) !vk.VkDevice {
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
        log.debug(@src(), "(PhysicalDevice)({s<8}) Extension version: {d}.{d}.{d} Name: {s}", .{
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

    var features_2 = vk.VkPhysicalDeviceFeatures2{
        .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
    };
    var stats: vk.VkPhysicalDevicePipelineExecutablePropertiesFeaturesKHR = .{
        .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PIPELINE_EXECUTABLE_PROPERTIES_FEATURES_KHR,
    };
    features_2.pNext = &stats;
    var physical_device_features: PDF = .{};
    if (instance.has_properties_2) {
        stats.pNext = physical_device_features.chain_supported(all_extension_names);
        vk.vkGetPhysicalDeviceFeatures2KHR.?(physical_device.device, &features_2);
    } else vk.vkGetPhysicalDeviceFeatures.?(physical_device.device, &features_2.features);

    // TODO add a robustness2 check for older dxvk/vkd3d databases.
    // TODO filter feateres_2 and extension_names based on the device_features2
    _ = device_features2;

    const enabled_layers = if (enable_validation) &VK_VALIDATION_LAYERS_NAMES else &.{};

    const create_info = vk.VkDeviceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pQueueCreateInfos = &queue_create_info,
        .queueCreateInfoCount = 1,
        .ppEnabledLayerNames = @ptrCast(enabled_layers.ptr),
        .enabledLayerCount = @as(u32, @intCast(enabled_layers.len)),
        .ppEnabledExtensionNames = all_extension_names.ptr,
        .enabledExtensionCount = @as(u32, @intCast(all_extension_names.len)),
        .pEnabledFeatures = if (instance.has_properties_2) null else &features_2.features,
        .pNext = if (instance.has_properties_2) &features_2 else null,
    };

    var vk_device: vk.VkDevice = undefined;
    try vu.check_result(vk.vkCreateDevice.?(
        physical_device.device,
        &create_info,
        null,
        &vk_device,
    ));
    return vk_device;
}

pub fn create_vk_sampler(
    vk_device: vk.VkDevice,
    create_info: *const vk.VkSamplerCreateInfo,
) !vk.VkSampler {
    var sampler: vk.VkSampler = undefined;
    try vu.check_result(vk.vkCreateSampler.?(
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
    try vu.check_result(vk.vkCreateDescriptorSetLayout.?(
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
    try vu.check_result(vk.vkCreatePipelineLayout.?(
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
    try vu.check_result(vk.vkCreateShaderModule.?(
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
    create_info: *const vk.VkRenderPassCreateInfo,
) !vk.VkRenderPass {
    var render_pass: vk.VkRenderPass = undefined;
    try vu.check_result(vk.vkCreateRenderPass.?(
        vk_device,
        create_info,
        null,
        &render_pass,
    ));
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
    try vu.check_result(vk.vkCreateGraphicsPipelines.?(
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
    try vu.check_result(vk.vkCreateComputePipelines.?(
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
    try vu.check_result(vk.vkCreateRayTracingPipelinesKHR.?(
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
