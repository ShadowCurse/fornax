const std = @import("std");
const vk = @import("vk.zig");
const log = @import("log.zig");

const LAYER_NAME = "VK_LAYER_fornax_capture";
const LAYER_DESCRIPTION = "Layer for capturing shader pipelines";

var next_vkGetInstanceProcAddr: *const vk.vkGetInstanceProcAddr = undefined;
var next_vkGetDeviceProcAddr: *const vk.vkGetDeviceProcAddr = undefined;

export fn layer_vkGetInstanceProcAddr(
    instance: vk.VkInstance,
    pName: [*:0]const u8,
) callconv(.c) ?*const vk.vkVoidFunction {
    log.info(@src(), "Requested name: {s}", .{pName});
    if (std.mem.eql(u8, std.mem.span(pName), "vkGetInstanceProcAddr"))
        return @ptrCast(&layer_vkGetInstanceProcAddr);
    if (std.mem.eql(u8, std.mem.span(pName), "vkEnumerateInstanceLayerProperties"))
        return @ptrCast(&layer_vkEnumerateInstanceLayerProperties);
    if (std.mem.eql(u8, std.mem.span(pName), "vkEnumerateInstanceExtensionProperties"))
        return @ptrCast(&layer_vkEnumerateInstanceExtensionProperties);
    if (std.mem.eql(u8, std.mem.span(pName), "vkCreateInstance"))
        return @ptrCast(&layer_vkCreateInstance);
    if (std.mem.eql(u8, std.mem.span(pName), "vkGetDeviceProcAddr"))
        return @ptrCast(&layer_vkGetDeviceProcAddr);
    if (std.mem.eql(u8, std.mem.span(pName), "vkEnumerateDeviceLayerProperties"))
        return @ptrCast(&layer_vkEnumerateDeviceLayerProperties);
    if (std.mem.eql(u8, std.mem.span(pName), "vkCreateDevice"))
        return @ptrCast(&layer_vkCreateDevice);

    return next_vkGetInstanceProcAddr(instance, pName);
}

fn layer_vkEnumerateInstanceLayerProperties(
    pPropertyCount: ?*u32,
    pProperties: ?[*]vk.VkLayerProperties,
) callconv(.c) vk.VkResult {
    if (pPropertyCount) |count| count.* = 1;

    if (pProperties) |props| {
        @memcpy(props[0].layerName[0..LAYER_NAME.len], LAYER_NAME);
        @memcpy(props[0].description[0..LAYER_DESCRIPTION.len], LAYER_DESCRIPTION);
        props[0].implementationVersion = vk.ApiVersion{ .patch = 1 };
        props[0].specVersion = vk.VK_API_VERSION_1_0;
    }

    return .VK_SUCCESS;
}

fn layer_vkEnumerateInstanceExtensionProperties(
    pLayerName: ?[*:0]const u8,
    pPropertyCount: ?*u32,
    pProperties: ?[*]vk.VkExtensionProperties,
) callconv(.c) vk.VkResult {
    _ = pProperties;
    if (pLayerName) |name| {
        if (std.mem.eql(u8, std.mem.span(name), "VK_LAYER_SAMPLE_SampleLayer")) {
            if (pPropertyCount) |count| count.* = 0;
            return .VK_SUCCESS;
        }
    }
    return .VK_ERROR_LAYER_NOT_PRESENT;
}

fn layer_vkCreateInstance(
    pCreateInfo: *const vk.VkInstanceCreateInfo,
    pAllocator: ?*const vk.VkAllocationCallbacks,
    pInstance: *vk.VkInstance,
) callconv(.c) vk.VkResult {
    var layer_create_info: ?*VkLayerInstanceCreateInfo = @ptrCast(@alignCast(@constCast(pCreateInfo.pNext)));
    while (layer_create_info) |info| {
        if (info.sType != .VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO or info.function != .VK_LAYER_LINK_INFO)
            layer_create_info = @ptrCast(@alignCast(@constCast(info.pNext)))
        else
            break;
    }

    if (layer_create_info) |info| {
        if (info.u.pLayerInfo) |layer_info| {
            next_vkGetInstanceProcAddr = layer_info.pfnNextGetInstanceProcAddr;
            info.u.pLayerInfo = layer_info.pNext;

            const vkCreateInstance: *const vk.vkCreateInstance =
                @ptrCast(next_vkGetInstanceProcAddr(.none, "vkCreateInstance"));

            return vkCreateInstance(pCreateInfo, pAllocator, pInstance);
        }
    }
    return .VK_ERROR_INITIALIZATION_FAILED;
}

export fn layer_vkGetDeviceProcAddr(
    device: vk.VkDevice,
    pName: [*:0]const u8,
) callconv(.c) ?*const vk.vkVoidFunction {
    if (std.mem.eql(u8, std.mem.span(pName), "vkGetDeviceProcAddr"))
        return @ptrCast(&layer_vkGetDeviceProcAddr);
    if (std.mem.eql(u8, std.mem.span(pName), "vkEnumerateDeviceLayerProperties"))
        return @ptrCast(&layer_vkEnumerateDeviceLayerProperties);
    if (std.mem.eql(u8, std.mem.span(pName), "vkCreateDevice"))
        return @ptrCast(&layer_vkCreateDevice);

    return next_vkGetDeviceProcAddr(device, pName);
}

fn layer_vkEnumerateDeviceLayerProperties(
    physicalDevice: vk.VkPhysicalDevice,
    pPropertyCount: *u32,
    pProperties: ?[*]vk.VkLayerProperties,
) callconv(.c) vk.VkResult {
    _ = physicalDevice;
    return layer_vkEnumerateInstanceLayerProperties(pPropertyCount, pProperties);
}

fn layer_vkCreateDevice(
    physicalDevice: vk.VkPhysicalDevice,
    pCreateInfo: *const vk.VkDeviceCreateInfo,
    pAllocator: ?*const vk.VkAllocationCallbacks,
    pDevice: *vk.VkDevice,
) callconv(.c) vk.VkResult {
    var layer_create_info: ?*VkLayerDeviceCreateInfo = @ptrCast(@alignCast(@constCast(pCreateInfo.pNext)));
    while (layer_create_info) |info| {
        if (info.sType != .VK_STRUCTURE_TYPE_LOADER_DEVICE_CREATE_INFO or info.function != .VK_LAYER_LINK_INFO)
            layer_create_info = @ptrCast(@alignCast(@constCast(info.pNext)))
        else
            break;
    }

    if (layer_create_info) |info| {
        if (info.u.pLayerInfo) |layer_info| {
            next_vkGetDeviceProcAddr = layer_info.pfnNextGetDeviceProcAddr;
            info.u.pLayerInfo = layer_info.pNext;

            const vkCreateDevice: *const vk.vkCreateDevice =
                @ptrCast(next_vkGetInstanceProcAddr(.none, "vkCreateDevice"));

            return vkCreateDevice(physicalDevice, pCreateInfo, pAllocator, pDevice);
        }
    }
    return .VK_ERROR_INITIALIZATION_FAILED;
}

const VkLayerFunction = enum(u32) {
    VK_LAYER_LINK_INFO = 0,
    VK_LOADER_DATA_CALLBACK = 1,
    VK_LOADER_LAYER_CREATE_DEVICE_CALLBACK = 2,
    VK_LOADER_FEATURES = 3,
};
const GetPhysicalDeviceProcAddr = fn (vk.VkInstance, [*:0]const u8) callconv(.c) *const vk.vkVoidFunction;
const VkLayerInstanceLink = extern struct {
    pNext: ?*const VkLayerInstanceLink = null,
    pfnNextGetInstanceProcAddr: *const vk.vkGetInstanceProcAddr,
    pfnNextGetPhysicalDeviceProcAddr: *const GetPhysicalDeviceProcAddr,
};

const vkSetInstanceLoaderData = fn (vk.VkInstance, ?*anyopaque) callconv(.c) vk.VkResult;
const vkSetDeviceLoaderData = fn (vk.VkDevice, ?*anyopaque) callconv(.c) vk.VkResult;
const vkLayerCreateDevice = fn (
    vk.VkInstance,
    vk.VkPhysicalDevice,
    [*c]const vk.VkDeviceCreateInfo,
    [*c]const vk.VkAllocationCallbacks,
    [*c]vk.VkDevice,
    *const vk.vkGetInstanceProcAddr,
    *const vk.vkGetDeviceProcAddr,
) callconv(.c) vk.VkResult;
const vkLayerDestroyDevice = fn (
    vk.VkDevice,
    *const vk.VkAllocationCallbacks,
    *const vk.vkDestroyDevice,
) callconv(.c) void;
const VkLoaderFeatureFlags = enum(u32) {
    VK_LOADER_FEATURE_PHYSICAL_DEVICE_SORTING = 1,
};
const VkLayerInstanceCreateInfo = extern struct {
    sType: vk.VkStructureType = .VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    function: VkLayerFunction,
    u: extern union {
        pLayerInfo: ?*const VkLayerInstanceLink,
        pfnSetInstanceLoaderData: *const vkSetInstanceLoaderData,
        layerDevice: extern struct {
            pfnLayerCreateDevice: *const vkLayerCreateDevice,
            pfnLayerDestroyDevice: *const vkLayerDestroyDevice,
        },
        loaderFeatures: VkLoaderFeatureFlags,
    },
};

const VkLayerDeviceLink = extern struct {
    pNext: ?*const VkLayerDeviceLink,
    pfnNextGetInstanceProcAddr: *const vk.vkGetInstanceProcAddr,
    pfnNextGetDeviceProcAddr: *const vk.vkGetDeviceProcAddr,
};
const VkLayerDeviceCreateInfo = extern struct {
    sType: vk.VkStructureType = .VK_STRUCTURE_TYPE_LOADER_DEVICE_CREATE_INFO,
    pNext: ?*const anyopaque,
    function: VkLayerFunction,
    u: extern union {
        pLayerInfo: ?*const VkLayerDeviceLink,
        pfnSetDeviceLoaderData: *const vkSetDeviceLoaderData,
    },
};
