const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("mach-glfw");
const vk = @import("vulkan");
const mach = @import("mach");
const zigimg = @import("zigimg");
const obj = @import("obj");
const textures = @import("textures");
const models = @import("models");

const vert = @embedFile("vert");
const frag = @embedFile("frag");

const assert = std.debug.assert;

const vertex = Vertex.init;
const vec2 = mach.math.vec2;
const vec3 = mach.math.vec3;
const vec4 = mach.math.vec4;
const mat4 = mach.math.mat4x4;
const Vec2 = mach.math.Vec2;
const Vec3 = mach.math.Vec3;
const Vec4 = mach.math.Vec4;
const Mat4x4 = mach.math.Mat4x4;

const width = 800;
const height = 600;
const max_frames_in_flight = 2;
var current_frame: u32 = 0;

const validation_layers = [_][*:0]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const device_extensions = [_][*:0]const u8{
    vk.extensions.khr_swapchain.name,
};

const UserPointer = struct {
    self: *HelloTriangleApplication,
};

const enable_validation_layers =
    if (builtin.mode == std.builtin.Mode.Debug) true else false;

var allocator: std.mem.Allocator = std.heap.page_allocator;
var vkb: BaseDispatch = undefined;
var vki: InstanceDispatch = undefined;
var vkd: DeviceDispatch = undefined;

// NOTE: Default GLFW error handling callback
fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.err("glfw: {}: {s}\n", .{ error_code, description });
}

const BaseDispatch = vk.BaseWrapper(&.{.{
    .base_commands = .{
        .createInstance = true,
        .enumerateInstanceExtensionProperties = true,
        .enumerateInstanceLayerProperties = true,
        .getInstanceProcAddr = true,
    },
}});

const InstanceDispatch = vk.InstanceWrapper(&.{
    .{
        .instance_commands = .{
            .createDevice = true,
            .enumeratePhysicalDevices = true,
            .enumerateDeviceExtensionProperties = true,
            .getPhysicalDeviceProperties = true,
            .getPhysicalDeviceFormatProperties = true,
            .getPhysicalDeviceFeatures = true,
            .getPhysicalDeviceQueueFamilyProperties = true,
            .getPhysicalDeviceSurfaceSupportKHR = true,
            .getPhysicalDeviceSurfaceCapabilitiesKHR = true,
            .getPhysicalDeviceSurfaceFormatsKHR = true,
            .getPhysicalDeviceSurfacePresentModesKHR = true,
            .getPhysicalDeviceMemoryProperties = true,
            .destroyInstance = true,
            .destroySurfaceKHR = true,
            .getDeviceProcAddr = true,
        },
    },
});

const DeviceDispatch = vk.DeviceWrapper(&.{
    .{
        .device_commands = .{
            .acquireNextImageKHR = true,
            .allocateCommandBuffers = true,
            .allocateMemory = true,
            .allocateDescriptorSets = true,
            .beginCommandBuffer = true,
            .bindBufferMemory = true,
            .bindImageMemory = true,
            .cmdBindPipeline = true,
            .cmdBeginRenderPass = true,
            .cmdSetViewport = true,
            .cmdSetScissor = true,
            .cmdBindVertexBuffers = true,
            .cmdBindIndexBuffer = true,
            .cmdDraw = true,
            .cmdDrawIndexed = true,
            .cmdEndRenderPass = true,
            .cmdCopyBuffer = true,
            .cmdBindDescriptorSets = true,
            .cmdCopyBufferToImage = true,
            .cmdPipelineBarrier = true,
            .cmdBlitImage = true,
            .createSwapchainKHR = true,
            .createImageView = true,
            .createShaderModule = true,
            .createRenderPass = true,
            .createPipelineLayout = true,
            .createGraphicsPipelines = true,
            .createFramebuffer = true,
            .createCommandPool = true,
            .createSemaphore = true,
            .createFence = true,
            .createBuffer = true,
            .createDescriptorSetLayout = true,
            .createDescriptorPool = true,
            .createImage = true,
            .createSampler = true,
            .destroyDevice = true,
            .destroySwapchainKHR = true,
            .destroyImageView = true,
            .destroyShaderModule = true,
            .destroyPipelineLayout = true,
            .destroyRenderPass = true,
            .destroyPipeline = true,
            .destroyFramebuffer = true,
            .destroyCommandPool = true,
            .destroySemaphore = true,
            .destroyFence = true,
            .destroyBuffer = true,
            .destroyDescriptorSetLayout = true,
            .destroyDescriptorPool = true,
            .destroyImage = true,
            .destroySampler = true,
            .deviceWaitIdle = true,
            .endCommandBuffer = true,
            .freeMemory = true,
            .freeCommandBuffers = true,
            .getDeviceQueue = true,
            .getSwapchainImagesKHR = true,
            .getBufferMemoryRequirements = true,
            .getImageMemoryRequirements = true,
            .mapMemory = true,
            .queueSubmit = true,
            .queuePresentKHR = true,
            .queueWaitIdle = true,
            .resetFences = true,
            .resetCommandBuffer = true,
            .unmapMemory = true,
            .updateDescriptorSets = true,
            .waitForFences = true,
        },
    },
});

const QueueFamilyIndices = struct {
    graphics_family: ?u32 = null,
    present_family: ?u32 = null,
    transfer_family: ?u32 = null,
    slice: []u32 = undefined,
};

const SwapChainSupportDetails = struct {
    capabilities: vk.SurfaceCapabilitiesKHR,
    formats: []vk.SurfaceFormatKHR,
    present_modes: []vk.PresentModeKHR,
};

const UniformBufferObject = struct {
    model: Mat4x4,
    view: Mat4x4,
    proj: Mat4x4,
};

const Vertex = struct {
    pos: Vec3,
    color: Vec3,
    tex_coord: Vec2,

    pub fn init(pos: Vec3, color: Vec3, tex_coord: Vec2) Vertex {
        return .{ .pos = pos, .color = color, .tex_coord = tex_coord };
    }

    pub const HashContext = struct {
        pub fn hash(_: HashContext, v: Vertex) u64 {
            var h = std.hash.Wyhash.init(0);

            h.update(std.mem.asBytes(&v.pos));
            h.update(std.mem.asBytes(&v.color));
            h.update(std.mem.asBytes(&v.tex_coord));

            return h.final();
        }

        pub fn eql(_: HashContext, a: Vertex, b: Vertex) bool {
            return a.pos.x() == b.pos.x() and
                a.pos.y() == b.pos.y() and
                a.pos.z() == b.pos.z() and
                a.color.x() == b.color.x() and
                a.color.y() == b.color.y() and
                a.color.z() == b.color.z() and
                a.tex_coord.x() == b.tex_coord.x() and
                a.tex_coord.y() == b.tex_coord.y();
        }
    };

    fn getBindingDescription() vk.VertexInputBindingDescription {
        const result = vk.VertexInputBindingDescription{
            .binding = 0,
            .stride = @sizeOf(Vertex),
            .input_rate = .vertex,
        };

        return result;
    }

    fn getAttributeDescriptions() ![]vk.VertexInputAttributeDescription {
        var result = try allocator.alloc(vk.VertexInputAttributeDescription, 3);

        result[0].binding = 0;
        result[0].location = 0;
        result[0].format = .r32g32b32_sfloat;
        result[0].offset = @offsetOf(Vertex, "pos");

        result[1].binding = 0;
        result[1].location = 1;
        result[1].format = .r32g32b32_sfloat;
        result[1].offset = @offsetOf(Vertex, "color");

        result[2].binding = 0;
        result[2].location = 2;
        result[2].format = .r32g32_sfloat;
        result[2].offset = @offsetOf(Vertex, "tex_coord");

        return result;
    }
};

//var vertices = [_]Vertex{
//    vertex(vec3(-0.5, -0.5, 0), vec3(1, 0, 0), vec2(0, 0)),
//    vertex(vec3(0.5, -0.5, 0), vec3(0, 1, 0), vec2(1, 0)),
//    vertex(vec3(0.5, 0.5, 0), vec3(0, 0, 1), vec2(1, 1)),
//    vertex(vec3(-0.5, 0.5, 0), vec3(1, 1, 1), vec2(0, 1)),
//
//    vertex(vec3(-0.5, -0.5, -0.5), vec3(1, 0, 0), vec2(0, 0)),
//    vertex(vec3(0.5, -0.5, -0.5), vec3(0, 1, 0), vec2(1, 0)),
//    vertex(vec3(0.5, 0.5, -0.5), vec3(0, 0, 1), vec2(1, 1)),
//    vertex(vec3(-0.5, 0.5, -0.5), vec3(1, 1, 1), vec2(0, 1)),
//};
//
//var indices = [_]u32{ 0, 1, 2, 2, 3, 0, 4, 5, 6, 6, 7, 4 };

fn printAvailableExtensions(available_extensions: []vk.ExtensionProperties) void {
    std.debug.print("available extensions:\n", .{});

    for (available_extensions) |extension| {
        const len = std.mem.indexOfScalar(u8, &extension.extension_name, 0).?;
        const extension_name = extension.extension_name[0..len];
        std.debug.print("\t{s}\n", .{extension_name});
    }
}

fn assertRequiredExtensionsAreSupported(
    glfw_extensions: [][*:0]const u8,
    available_extensions: []vk.ExtensionProperties,
) void {
    for (glfw_extensions) |glfw_extension| {
        var extension_is_available = false;

        for (available_extensions) |extension| {
            const len = std.mem.indexOfScalar(u8, &extension.extension_name, 0).?;
            const extension_name = extension.extension_name[0..len];

            if (std.mem.eql(u8, extension_name, std.mem.span(glfw_extension))) {
                extension_is_available = true;

                break;
            }
        }

        assert(extension_is_available);
    }
}

fn checkValidationLayerSupport() !bool {
    var layer_count: u32 = undefined;

    _ = try vkb.enumerateInstanceLayerProperties(&layer_count, null);
    const available_layers = try allocator.alloc(vk.LayerProperties, layer_count);
    defer allocator.free(available_layers);
    _ = try vkb.enumerateInstanceLayerProperties(&layer_count, available_layers.ptr);

    for (validation_layers) |layer| {
        var layer_found = false;

        for (available_layers) |prop| {
            const len = std.mem.indexOfScalar(u8, &prop.layer_name, 0).?;
            const layer_name = prop.layer_name[0..len];

            if (std.mem.eql(u8, std.mem.span(layer), layer_name)) {
                layer_found = true;
                break;
            }
        }

        if (!layer_found) {
            return false;
        }
    }

    return true;
}

fn getRequiredExtensions() !std.ArrayList([*:0]const u8) {
    const glfw_extensions = glfw.getRequiredInstanceExtensions() orelse return blk: {
        const err = glfw.mustGetError();

        std.log.err(
            "failed to get required vulkan instance extensions: error={s}",
            .{err.description},
        );

        break :blk error.code;
    };

    var instance_extensions = try std.ArrayList([*:0]const u8)
        .initCapacity(allocator, glfw_extensions.len);

    try instance_extensions.appendSlice(glfw_extensions);

    if (enable_validation_layers) {
        try instance_extensions.append(vk.extensions.ext_debug_utils.name);
    }

    if (builtin.os.tag == .macos) {
        try instance_extensions.append(@ptrCast(
            vk.extensions.khr_portability_enumeration.name,
        ));
    }

    var extension_count: u32 = undefined;
    _ = try vkb.enumerateInstanceExtensionProperties(null, &extension_count, null);

    const available_extensions = try allocator.alloc(vk.ExtensionProperties, extension_count);
    defer allocator.free(available_extensions);

    _ = try vkb.enumerateInstanceExtensionProperties(
        null,
        &extension_count,
        available_extensions.ptr,
    );

    printAvailableExtensions(available_extensions);
    assertRequiredExtensionsAreSupported(glfw_extensions, available_extensions);

    return instance_extensions;
}

fn createDebugUtilsMessengerEXT(
    instance: vk.Instance,
    p_create_info: *const vk.DebugUtilsMessengerCreateInfoEXT,
    p_allocator: ?*const vk.AllocationCallbacks,
    p_debug_messenger: *vk.DebugUtilsMessengerEXT,
) !vk.Result {
    var result: vk.Result = undefined;

    const maybe_func = @as(
        ?vk.PfnCreateDebugUtilsMessengerEXT,
        @ptrCast(vkb.getInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT")),
    );

    if (maybe_func) |func| {
        result = func(instance, p_create_info, p_allocator, p_debug_messenger);
    } else {
        result = .error_extension_not_present;
    }

    return result;
}

fn destroyDebugUtilsMessengerEXT(
    instance: vk.Instance,
    debug_messenger: vk.DebugUtilsMessengerEXT,
    p_allocator: ?*const vk.AllocationCallbacks,
) void {
    const maybe_func = @as(
        ?vk.PfnDestroyDebugUtilsMessengerEXT,
        @ptrCast(vkb.getInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT")),
    );

    if (maybe_func) |func| {
        func(instance, debug_messenger, p_allocator);
    }
}

fn querySwapChainSupport(
    app: *HelloTriangleApplication,
    device: vk.PhysicalDevice,
) !SwapChainSupportDetails {
    var result: SwapChainSupportDetails = undefined;

    result.capabilities = try vki.getPhysicalDeviceSurfaceCapabilitiesKHR(device, app.surface);

    var format_count: u32 = undefined;
    _ = try vki.getPhysicalDeviceSurfaceFormatsKHR(device, app.surface, &format_count, null);

    if (format_count != 0) {
        result.formats = try allocator.alloc(vk.SurfaceFormatKHR, format_count);
        _ = try vki.getPhysicalDeviceSurfaceFormatsKHR(device, app.surface, &format_count, result.formats.ptr);
    }

    var present_mode_count: u32 = undefined;
    _ = try vki.getPhysicalDeviceSurfacePresentModesKHR(device, app.surface, &present_mode_count, null);

    if (present_mode_count != 0) {
        result.present_modes = try allocator.alloc(vk.PresentModeKHR, present_mode_count);
        _ = try vki.getPhysicalDeviceSurfacePresentModesKHR(device, app.surface, &present_mode_count, result.present_modes.ptr);
    }

    return result;
}

fn chooseSwapSurfaceFormat(available_formats: []const vk.SurfaceFormatKHR) vk.SurfaceFormatKHR {
    for (available_formats) |format| {
        if (format.format == .b8g8r8a8_srgb and format.color_space == .srgb_nonlinear_khr) {
            return format;
        }
    }

    return available_formats[0];
}

fn chooseSwapPresentMode(available_present_modes: []const vk.PresentModeKHR) vk.PresentModeKHR {
    for (available_present_modes) |present_mode| {
        if (present_mode == .mailbox_khr) {
            return present_mode;
        }
    }

    return vk.PresentModeKHR.fifo_khr;
}

fn chooseSwapExtent(
    window: glfw.Window,
    capabilities: *const vk.SurfaceCapabilitiesKHR,
) vk.Extent2D {
    if (capabilities.current_extent.width != std.math.maxInt(u32)) {
        return capabilities.current_extent;
    } else {
        const size = window.getFramebufferSize();

        var actual_extent = vk.Extent2D{ .width = size.width, .height = size.height };

        actual_extent.width = std.math.clamp(
            actual_extent.width,
            capabilities.min_image_extent.width,
            capabilities.max_image_extent.width,
        );
        actual_extent.height = std.math.clamp(
            actual_extent.height,
            capabilities.min_image_extent.height,
            capabilities.max_image_extent.height,
        );

        return actual_extent;
    }
}

const HelloTriangleApplication = struct {
    user_ptr: UserPointer = undefined,
    instance: vk.Instance = .null_handle,
    debug_messenger: vk.DebugUtilsMessengerEXT = .null_handle,
    physical_device: vk.PhysicalDevice = .null_handle,
    device: vk.Device = .null_handle,
    surface: vk.SurfaceKHR = .null_handle,
    graphics_queue: vk.Queue = .null_handle,
    present_queue: vk.Queue = .null_handle,
    transfer_queue: vk.Queue = .null_handle,
    swap_chain: vk.SwapchainKHR = .null_handle,
    swap_chain_images: []vk.Image = undefined,
    swap_chain_image_format: vk.Format = .undefined,
    swap_chain_extent: vk.Extent2D = undefined,
    swap_chain_image_views: []vk.ImageView = undefined,
    render_pass: vk.RenderPass = .null_handle,
    descriptor_set_layout: vk.DescriptorSetLayout = .null_handle,
    pipeline_layout: vk.PipelineLayout = .null_handle,
    graphics_pipeline: vk.Pipeline = .null_handle,
    swap_chain_framebuffers: []vk.Framebuffer = undefined,
    command_pool: vk.CommandPool = .null_handle,
    transfer_command_pool: vk.CommandPool = .null_handle,
    command_buffers: []vk.CommandBuffer = undefined,
    image_available_semaphores: []vk.Semaphore = undefined,
    render_finished_semaphores: []vk.Semaphore = undefined,
    in_flight_fences: []vk.Fence = undefined,
    framebuffer_resized: bool = false,
    vertices: std.ArrayList(Vertex) = undefined,
    indices: std.ArrayList(u32) = undefined,
    vertex_buffer: vk.Buffer = .null_handle,
    vertex_buffer_memory: vk.DeviceMemory = .null_handle,
    index_buffer: vk.Buffer = .null_handle,
    index_buffer_memory: vk.DeviceMemory = .null_handle,
    uniform_buffers: []vk.Buffer = undefined,
    uniform_buffer_memory: []vk.DeviceMemory = undefined,
    uniform_buffers_mapped: []?*anyopaque = undefined,
    timer: std.time.Timer = undefined,
    descriptor_pool: vk.DescriptorPool = .null_handle,
    descriptor_sets: []vk.DescriptorSet = undefined,
    mip_levels: u32 = undefined,
    texture_image: vk.Image = .null_handle,
    texture_image_memory: vk.DeviceMemory = .null_handle,
    texture_image_view: vk.ImageView = .null_handle,
    texture_sampler: vk.Sampler = .null_handle,
    depth_image: vk.Image = .null_handle,
    depth_image_memory: vk.DeviceMemory = .null_handle,
    depth_image_view: vk.ImageView = .null_handle,
    msaa_samples: vk.SampleCountFlags = .{ .@"1_bit" = true },
    color_image: vk.Image = .null_handle,
    color_image_memory: vk.DeviceMemory = .null_handle,
    color_image_view: vk.ImageView = .null_handle,

    pub fn run(self: *HelloTriangleApplication) !void {
        self.timer = std.time.Timer{
            .started = try std.time.Instant.now(),
            .previous = try std.time.Instant.now(),
        };

        self.vertices = std.ArrayList(Vertex).init(allocator);
        defer self.vertices.deinit();
        self.indices = std.ArrayList(u32).init(allocator);
        defer self.indices.deinit();

        // NOTE: Storing a reference to the glfw window seems to cause all sorts of problems
        // where the pointer is resolving to null and causing seg faults, so we pull it out
        // here instead
        const window = initWindow(self);
        defer glfw.terminate();
        defer window.destroy();
        try initVulkan(self, window);
        defer cleanup(self);
        try mainLoop(self, window);
    }

    fn initWindow(self: *HelloTriangleApplication) glfw.Window {
        self.user_ptr = .{ .self = self };

        glfw.setErrorCallback(errorCallback);
        if (!glfw.init(.{})) {
            std.log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
            std.process.exit(1);
        }

        const glfw_window = glfw.Window.create(width, height, "Vulkan", null, null, .{
            .client_api = .no_api,
        }) orelse {
            std.log.err("failed to create GLFW window: {?s}", .{glfw.getErrorString()});
            std.process.exit(1);
        };

        glfw_window.setUserPointer(&self.user_ptr);

        const framebuffer_size_callback = struct {
            fn callback(window: glfw.Window, _: u32, _: u32) void {
                const app = (window.getUserPointer(UserPointer) orelse unreachable).self;
                app.framebuffer_resized = true;
            }
        }.callback;

        glfw_window.setFramebufferSizeCallback(framebuffer_size_callback);

        return glfw_window;
    }

    // TODO: Consider a procedural refactoring of this struct and all its member functions, many of which
    // do not seem to see any reuse. Maybe a larger app would see some of these functions being called more
    // than once?
    fn initVulkan(self: *HelloTriangleApplication, window: glfw.Window) !void {
        try createInstance(self);
        setupDebugMessenger(self);
        try createSurface(self, window);
        try pickPhysicalDevice(self);
        try createLogicalDevice(self);
        try createSwapChain(self, window, .null_handle);
        try createImageViews(self);
        try createRenderPass(self);
        try createDescriptorSetLayout(self);
        try createGraphicsPipeline(self);
        try createCommandPool(self);
        try createColorResources(self);
        try createDepthResources(self);
        try createFramebuffers(self);
        try createTextureImage(self);
        try createTextureImageView(self);
        try createTextureSampler(self);
        try loadModel(self);
        try createVertexBuffer(self);
        try createIndexBuffer(self);
        try createUniformBuffers(self);
        try createDescriptorPool(self);
        try createDescriptorSets(self);
        try createCommandBuffers(self);
        try createSyncObjects(self);
    }

    fn createColorResources(self: *HelloTriangleApplication) !void {
        const color_format = self.swap_chain_image_format;

        try createImage(
            self,
            self.swap_chain_extent.width,
            self.swap_chain_extent.height,
            1,
            self.msaa_samples,
            color_format,
            .optimal,
            .{ .transient_attachment_bit = true, .color_attachment_bit = true },
            .{ .device_local_bit = true },
            &self.color_image,
            &self.color_image_memory,
        );

        self.color_image_view = try createImageView(self, self.color_image, color_format, .{ .color_bit = true }, 1);
    }

    fn getMaxUsableSampleCount(self: *HelloTriangleApplication) vk.SampleCountFlags {
        const physical_device_properties = vki.getPhysicalDeviceProperties(self.physical_device);

        const counts = physical_device_properties.limits.framebuffer_color_sample_counts.intersect(
            physical_device_properties.limits.framebuffer_depth_sample_counts,
        );

        if (counts.@"64_bit") return .{ .@"64_bit" = true };
        if (counts.@"32_bit") return .{ .@"32_bit" = true };
        if (counts.@"16_bit") return .{ .@"16_bit" = true };
        if (counts.@"8_bit") return .{ .@"8_bit" = true };
        if (counts.@"4_bit") return .{ .@"4_bit" = true };
        if (counts.@"2_bit") return .{ .@"2_bit" = true };

        return .{ .@"1_bit" = true };
    }

    fn loadModel(self: *HelloTriangleApplication) !void {
        var model = try obj.parseObj(allocator, models.viking_room_obj);
        defer model.deinit(allocator);

        var unique_vertices = std.HashMap(Vertex, u32, Vertex.HashContext, std.hash_map.default_max_load_percentage).init(allocator);
        defer unique_vertices.deinit();

        for (model.meshes) |mesh| {
            for (mesh.indices) |index| {
                var v: Vertex = undefined;

                v.pos = vec3(
                    model.vertices[3 * index.vertex.? + 0],
                    model.vertices[3 * index.vertex.? + 1],
                    model.vertices[3 * index.vertex.? + 2],
                );

                v.tex_coord = vec2(
                    model.tex_coords[2 * index.tex_coord.? + 0],
                    1.0 - model.tex_coords[2 * index.tex_coord.? + 1],
                );

                v.color = Vec3.splat(1);

                if (unique_vertices.get(v) == null) {
                    try unique_vertices.put(v, @intCast(self.vertices.items.len));
                    try self.vertices.append(v);
                }

                try self.indices.append(unique_vertices.get(v).?);
            }
        }
    }

    fn createDepthResources(self: *HelloTriangleApplication) !void {
        const depth_format = findDepthFormat(self);

        try createImage(
            self,
            self.swap_chain_extent.width,
            self.swap_chain_extent.height,
            1,
            self.msaa_samples,
            depth_format,
            .optimal,
            .{ .depth_stencil_attachment_bit = true },
            .{ .device_local_bit = true },
            &self.depth_image,
            &self.depth_image_memory,
        );

        self.depth_image_view = try createImageView(self, self.depth_image, depth_format, .{ .depth_bit = true }, 1);

        try transitionImageLayout(self, self.depth_image, depth_format, .undefined, .depth_stencil_attachment_optimal, 1);
    }

    fn findSupportedFormat(
        self: *HelloTriangleApplication,
        candidates: []vk.Format,
        tiling: vk.ImageTiling,
        features: vk.FormatFeatureFlags,
    ) vk.Format {
        for (candidates) |format| {
            const props = vki.getPhysicalDeviceFormatProperties(self.physical_device, format);

            if (tiling == .linear and props.linear_tiling_features.contains(features)) {
                return format;
            } else if (tiling == .optimal and props.optimal_tiling_features.contains(features)) {
                return format;
            }
        }

        @panic("failed to find supported format!");
    }

    fn findDepthFormat(self: *HelloTriangleApplication) vk.Format {
        var candidates = [_]vk.Format{ .d32_sfloat, .d32_sfloat_s8_uint, .d24_unorm_s8_uint };

        return findSupportedFormat(
            self,
            @ptrCast(&candidates),
            .optimal,
            .{ .depth_stencil_attachment_bit = true },
        );
    }

    fn hasStencilComponent(format: vk.Format) bool {
        return format == .d32_sfloat_s8_uint or format == .d24_unorm_s8_uint;
    }

    fn createTextureSampler(self: *HelloTriangleApplication) !void {
        const properties = vki.getPhysicalDeviceProperties(self.physical_device);

        const sampler_info = vk.SamplerCreateInfo{
            .mag_filter = .linear,
            .min_filter = .linear,
            .address_mode_u = .repeat,
            .address_mode_v = .repeat,
            .address_mode_w = .repeat,
            .anisotropy_enable = vk.TRUE,
            .max_anisotropy = properties.limits.max_sampler_anisotropy,
            .border_color = .int_opaque_black,
            .unnormalized_coordinates = vk.FALSE,
            .compare_enable = vk.FALSE,
            .compare_op = .always,
            .mipmap_mode = .linear,
            .mip_lod_bias = 0,
            .min_lod = 0,
            .max_lod = @floatFromInt(self.mip_levels),
        };

        self.texture_sampler = try vkd.createSampler(self.device, &sampler_info, null);
    }

    fn createImageView(
        self: *HelloTriangleApplication,
        image: vk.Image,
        format: vk.Format,
        aspect_flags: vk.ImageAspectFlags,
        mip_levels: u32,
    ) !vk.ImageView {
        const view_info = vk.ImageViewCreateInfo{
            .image = image,
            .view_type = .@"2d",
            .format = format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .aspect_mask = aspect_flags,
                .base_mip_level = 0,
                .level_count = mip_levels,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        };

        const result = try vkd.createImageView(self.device, &view_info, null);

        return result;
    }

    fn createTextureImageView(self: *HelloTriangleApplication) !void {
        self.texture_image_view = try createImageView(self, self.texture_image, .r8g8b8a8_srgb, .{ .color_bit = true }, self.mip_levels);
    }

    fn copyBufferToImage(
        self: *HelloTriangleApplication,
        buffer: vk.Buffer,
        image: vk.Image,
        image_width: u32,
        image_height: u32,
    ) !void {
        const command_buffer = try beginSingleTimeCommands(self);

        var region = vk.BufferImageCopy{
            .buffer_offset = 0,
            .buffer_row_length = 0,
            .buffer_image_height = 0,
            .image_subresource = .{
                .aspect_mask = .{ .color_bit = true },
                .mip_level = 0,
                .base_array_layer = 0,
                .layer_count = 1,
            },
            .image_offset = .{ .x = 0, .y = 0, .z = 0 },
            .image_extent = .{
                .width = image_width,
                .height = image_height,
                .depth = 1,
            },
        };

        vkd.cmdCopyBufferToImage(command_buffer, buffer, image, .transfer_dst_optimal, 1, @ptrCast(&region));

        try endSingleTimeCommands(self, command_buffer);
    }

    fn transitionImageLayout(
        self: *HelloTriangleApplication,
        image: vk.Image,
        format: vk.Format,
        old_layout: vk.ImageLayout,
        new_layout: vk.ImageLayout,
        mip_levels: u32,
    ) !void {
        const command_buffer = try beginSingleTimeCommands(self);

        var barrier = vk.ImageMemoryBarrier{
            .old_layout = old_layout,
            .new_layout = new_layout,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = image,
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = mip_levels,
                .base_array_layer = 0,
                .layer_count = 1,
            },
            .src_access_mask = .{},
            .dst_access_mask = .{},
            .p_next = null,
        };

        var source_stage = vk.PipelineStageFlags{};
        var destination_stage = vk.PipelineStageFlags{};

        if (new_layout == .depth_stencil_attachment_optimal) {
            barrier.subresource_range.aspect_mask = .{ .depth_bit = true };

            if (hasStencilComponent(format)) {
                barrier.subresource_range.aspect_mask.stencil_bit = true;
            }
        } else {
            barrier.subresource_range.aspect_mask = .{ .color_bit = true };
        }

        if (old_layout == .undefined and new_layout == .transfer_dst_optimal) {
            barrier.src_access_mask = .{};
            barrier.dst_access_mask = .{ .transfer_write_bit = true };
            source_stage = .{ .top_of_pipe_bit = true };
            destination_stage = .{ .transfer_bit = true };
        } else if (old_layout == .transfer_dst_optimal and new_layout == .shader_read_only_optimal) {
            barrier.src_access_mask = .{ .transfer_write_bit = true };
            barrier.dst_access_mask = .{ .shader_read_bit = true };

            source_stage = .{ .transfer_bit = true };
            destination_stage = .{ .fragment_shader_bit = true };
        } else if (old_layout == .undefined and new_layout == .depth_stencil_attachment_optimal) {
            barrier.src_access_mask = .{};
            barrier.dst_access_mask = .{
                .depth_stencil_attachment_read_bit = true,
                .depth_stencil_attachment_write_bit = true,
            };

            source_stage = .{ .top_of_pipe_bit = true };
            destination_stage = .{ .early_fragment_tests_bit = true };
        } else {
            @panic("unsupported layout transition!");
        }

        vkd.cmdPipelineBarrier(
            command_buffer,
            source_stage,
            destination_stage,
            .{},
            0,
            null,
            0,
            null,
            1,
            @ptrCast(&barrier),
        );

        try endSingleTimeCommands(self, command_buffer);
    }

    fn createImage(
        self: *HelloTriangleApplication,
        image_width: u32,
        image_height: u32,
        mip_levels: u32,
        sample_count_flags: vk.SampleCountFlags,
        format: vk.Format,
        tiling: vk.ImageTiling,
        usage: vk.ImageUsageFlags,
        properties: vk.MemoryPropertyFlags,
        image: *vk.Image,
        image_memory: *vk.DeviceMemory,
    ) !void {
        var image_info = vk.ImageCreateInfo{
            .image_type = .@"2d",
            .extent = .{ .width = image_width, .height = image_height, .depth = 1 },
            .mip_levels = mip_levels,
            .array_layers = 1,
            .format = format,
            .tiling = tiling,
            .initial_layout = .undefined,
            .usage = usage,
            .sharing_mode = .exclusive,
            .samples = sample_count_flags,
            .flags = .{},
        };

        image.* = try vkd.createImage(self.device, &image_info, null);

        const mem_requirements = vkd.getImageMemoryRequirements(self.device, image.*);

        var alloc_info = vk.MemoryAllocateInfo{
            .allocation_size = mem_requirements.size,
            .memory_type_index = findMemoryType(self, mem_requirements.memory_type_bits, properties),
        };

        image_memory.* = try vkd.allocateMemory(self.device, &alloc_info, null);
        _ = try vkd.bindImageMemory(self.device, image.*, image_memory.*, 0);
    }

    fn createTextureImage(self: *HelloTriangleApplication) !void {
        var image = try zigimg.Image.fromMemory(allocator, textures.viking_room_png);
        defer image.deinit();
        try image.convert(.rgba32);

        self.mip_levels = @intFromFloat(@floor(@log2(@as(f32, @floatFromInt(@max(image.width, image.height))))) + 1);

        var staging_buffer: vk.Buffer = .null_handle;
        var staging_buffer_memory: vk.DeviceMemory = .null_handle;

        try createBuffer(
            self,
            image.imageByteSize(),
            .{ .transfer_src_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
            &staging_buffer,
            &staging_buffer_memory,
        );
        defer vkd.destroyBuffer(self.device, staging_buffer, null);
        defer vkd.freeMemory(self.device, staging_buffer_memory, null);

        const maybe_data = try vkd.mapMemory(self.device, staging_buffer_memory, 0, image.imageByteSize(), .{});
        defer vkd.unmapMemory(self.device, staging_buffer_memory);

        if (maybe_data) |data| @memcpy(
            @as([*]u8, @ptrCast(data))[0..image.imageByteSize()],
            @as([*]u8, @ptrCast(image.pixels.asBytes())),
        );

        try createImage(
            self,
            @intCast(image.width),
            @intCast(image.height),
            self.mip_levels,
            .{ .@"1_bit" = true },
            .r8g8b8a8_srgb,
            .optimal,
            .{ .transfer_src_bit = true, .transfer_dst_bit = true, .sampled_bit = true },
            .{ .device_local_bit = true },
            &self.texture_image,
            &self.texture_image_memory,
        );

        try transitionImageLayout(self, self.texture_image, .r8g8b8a8_srgb, .undefined, .transfer_dst_optimal, self.mip_levels);
        try copyBufferToImage(self, staging_buffer, self.texture_image, @intCast(image.width), @intCast(image.height));
        //try transitionImageLayout(self, self.texture_image, .r8g8b8a8_srgb, .transfer_dst_optimal, .shader_read_only_optimal, self.mip_levels);
        try generateMipmaps(self, self.texture_image, .r8g8b8a8_srgb, @intCast(image.width), @intCast(image.height), self.mip_levels);
    }

    // Implementing resizing in software and loading multiple levels from a file is left as an exercise to the reader.
    fn generateMipmaps(
        self: *HelloTriangleApplication,
        image: vk.Image,
        image_format: vk.Format,
        tex_width: i32,
        tex_height: i32,
        mip_levels: u32,
    ) !void {
        const format_properties = vki.getPhysicalDeviceFormatProperties(self.physical_device, image_format);

        if (!format_properties.optimal_tiling_features.sampled_image_filter_linear_bit) @panic("texture image format does not support linear blitting!");

        const command_buffer = try beginSingleTimeCommands(self);

        var barrier = vk.ImageMemoryBarrier{
            .image = image,
            .src_access_mask = .{},
            .dst_access_mask = .{},
            .old_layout = .undefined,
            .new_layout = .undefined,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .base_array_layer = 0,
                .layer_count = 1,
                .level_count = 1,
            },
        };

        var mip_width = tex_width;
        var mip_height = tex_height;

        for (1..mip_levels) |i| {
            barrier.subresource_range.base_mip_level = @intCast(i - 1);
            barrier.old_layout = .transfer_dst_optimal;
            barrier.new_layout = .transfer_src_optimal;
            barrier.src_access_mask = .{ .transfer_write_bit = true };
            barrier.dst_access_mask = .{ .transfer_read_bit = true };

            vkd.cmdPipelineBarrier(command_buffer, .{ .transfer_bit = true }, .{ .transfer_bit = true }, .{}, 0, null, 0, null, 1, @ptrCast(&barrier));

            const blit = vk.ImageBlit{
                .src_offsets = .{
                    .{ .x = 0, .y = 0, .z = 0 },
                    .{ .x = mip_width, .y = mip_height, .z = 1 },
                },
                .src_subresource = .{
                    .aspect_mask = .{ .color_bit = true },
                    .mip_level = @intCast(i - 1),
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
                .dst_offsets = .{
                    .{
                        .x = 0,
                        .y = 0,
                        .z = 0,
                    },
                    .{
                        .x = if (mip_width > 1) @divFloor(mip_width, 2) else 1,
                        .y = if (mip_height > 1) @divFloor(mip_height, 2) else 1,
                        .z = 1,
                    },
                },
                .dst_subresource = .{
                    .aspect_mask = .{ .color_bit = true },
                    .mip_level = @intCast(i),
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
            };

            vkd.cmdBlitImage(command_buffer, image, .transfer_src_optimal, image, .transfer_dst_optimal, 1, @ptrCast(&blit), .linear);

            barrier.old_layout = .transfer_src_optimal;
            barrier.new_layout = .shader_read_only_optimal;
            barrier.src_access_mask = .{ .transfer_read_bit = true };
            barrier.dst_access_mask = .{ .shader_read_bit = true };

            vkd.cmdPipelineBarrier(command_buffer, .{ .transfer_bit = true }, .{ .fragment_shader_bit = true }, .{}, 0, null, 0, null, 1, @ptrCast(&barrier));

            if (mip_width > 1) mip_width = @divFloor(mip_width, 2);
            if (mip_height > 1) mip_height = @divFloor(mip_height, 2);
        }

        barrier.subresource_range.base_mip_level = mip_levels - 1;
        barrier.old_layout = .transfer_dst_optimal;
        barrier.new_layout = .shader_read_only_optimal;
        barrier.src_access_mask = .{ .transfer_write_bit = true };
        barrier.dst_access_mask = .{ .shader_read_bit = true };

        vkd.cmdPipelineBarrier(command_buffer, .{ .transfer_bit = true }, .{ .fragment_shader_bit = true }, .{}, 0, null, 0, null, 1, @ptrCast(&barrier));

        try endSingleTimeCommands(self, command_buffer);
    }

    fn createDescriptorSets(self: *HelloTriangleApplication) !void {
        const layouts = [_]vk.DescriptorSetLayout{ self.descriptor_set_layout, self.descriptor_set_layout };

        const alloc_info = vk.DescriptorSetAllocateInfo{
            .descriptor_pool = self.descriptor_pool,
            .descriptor_set_count = max_frames_in_flight,
            .p_set_layouts = &layouts,
        };

        self.descriptor_sets = try allocator.alloc(vk.DescriptorSet, max_frames_in_flight);

        _ = try vkd.allocateDescriptorSets(self.device, &alloc_info, self.descriptor_sets.ptr);

        for (0..max_frames_in_flight) |i| {
            const buffer_info = vk.DescriptorBufferInfo{
                .buffer = self.uniform_buffers[i],
                .offset = 0,
                .range = @sizeOf(UniformBufferObject),
            };

            const image_info = vk.DescriptorImageInfo{
                .image_layout = .shader_read_only_optimal,
                .image_view = self.texture_image_view,
                .sampler = self.texture_sampler,
            };

            const descriptor_writes = [_]vk.WriteDescriptorSet{
                .{
                    .dst_set = self.descriptor_sets[i],
                    .dst_binding = 0,
                    .dst_array_element = 0,
                    .descriptor_type = .uniform_buffer,
                    .descriptor_count = 1,
                    .p_buffer_info = @ptrCast(&buffer_info),
                    .p_image_info = undefined,
                    .p_texel_buffer_view = undefined,
                },
                .{
                    .dst_set = self.descriptor_sets[i],
                    .dst_binding = 1,
                    .dst_array_element = 0,
                    .descriptor_type = .combined_image_sampler,
                    .descriptor_count = 1,
                    .p_buffer_info = undefined,
                    .p_image_info = @ptrCast(&image_info),
                    .p_texel_buffer_view = undefined,
                },
            };

            vkd.updateDescriptorSets(self.device, descriptor_writes.len, &descriptor_writes, 0, null);
        }
    }

    fn createDescriptorPool(self: *HelloTriangleApplication) !void {
        const pool_sizes = [_]vk.DescriptorPoolSize{
            .{
                .type = .uniform_buffer,
                .descriptor_count = max_frames_in_flight,
            },
            .{
                .type = .combined_image_sampler,
                .descriptor_count = max_frames_in_flight,
            },
        };

        const pool_info = vk.DescriptorPoolCreateInfo{
            .pool_size_count = pool_sizes.len,
            .p_pool_sizes = &pool_sizes,
            .max_sets = max_frames_in_flight,
        };

        self.descriptor_pool = try vkd.createDescriptorPool(self.device, &pool_info, null);
    }

    fn createUniformBuffers(self: *HelloTriangleApplication) !void {
        const buffer_size = @sizeOf(UniformBufferObject);

        self.uniform_buffers = try allocator.alloc(vk.Buffer, max_frames_in_flight);
        self.uniform_buffer_memory = try allocator.alloc(vk.DeviceMemory, max_frames_in_flight);
        self.uniform_buffers_mapped = try allocator.alloc(?*anyopaque, max_frames_in_flight);

        for (0..max_frames_in_flight) |i| {
            try createBuffer(
                self,
                buffer_size,
                .{ .uniform_buffer_bit = true },
                .{ .host_visible_bit = true, .host_coherent_bit = true },
                &self.uniform_buffers[i],
                &self.uniform_buffer_memory[i],
            );

            self.uniform_buffers_mapped[i] = try vkd.mapMemory(
                self.device,
                self.uniform_buffer_memory[i],
                0,
                buffer_size,
                .{},
            );
        }
    }

    fn createDescriptorSetLayout(self: *HelloTriangleApplication) !void {
        const ubo_layout_binding = vk.DescriptorSetLayoutBinding{
            .binding = 0,
            .descriptor_type = .uniform_buffer,
            .descriptor_count = 1,
            .stage_flags = .{ .vertex_bit = true },
            .p_immutable_samplers = null,
        };

        const sampler_layout_binding = vk.DescriptorSetLayoutBinding{
            .binding = 1,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_immutable_samplers = null,
            .stage_flags = .{ .fragment_bit = true },
        };

        const bindings = [_]vk.DescriptorSetLayoutBinding{ ubo_layout_binding, sampler_layout_binding };

        var layout_info = vk.DescriptorSetLayoutCreateInfo{
            .binding_count = bindings.len,
            .p_bindings = &bindings,
        };

        self.descriptor_set_layout = try vkd.createDescriptorSetLayout(self.device, &layout_info, null);
    }

    fn findMemoryType(
        self: *HelloTriangleApplication,
        type_filter: u32,
        properties: vk.MemoryPropertyFlags,
    ) u32 {
        const mem_properties = vki.getPhysicalDeviceMemoryProperties(self.physical_device);

        for (0..mem_properties.memory_type_count) |i| {
            const flags = mem_properties.memory_types[i].property_flags;

            if ((type_filter & (@as(u64, @intCast(1)) << @intCast(i))) > 0 and
                flags.contains(properties))
            {
                return @intCast(i);
            }
        }

        @panic("failed to find suitable memory type!");
    }

    fn beginSingleTimeCommands(self: *HelloTriangleApplication) !vk.CommandBuffer {
        const alloc_info = vk.CommandBufferAllocateInfo{
            .level = .primary,
            .command_pool = self.command_pool,
            .command_buffer_count = 1,
        };

        var command_buffer: vk.CommandBuffer = .null_handle;
        _ = try vkd.allocateCommandBuffers(self.device, &alloc_info, @ptrCast(&command_buffer));

        const begin_info = vk.CommandBufferBeginInfo{
            .flags = .{ .one_time_submit_bit = true },
        };

        _ = try vkd.beginCommandBuffer(command_buffer, &begin_info);

        return command_buffer;
    }

    fn endSingleTimeCommands(self: *HelloTriangleApplication, command_buffer: vk.CommandBuffer) !void {
        _ = try vkd.endCommandBuffer(command_buffer);

        const submit_info = vk.SubmitInfo{
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&command_buffer),
        };

        if (self.transfer_queue != .null_handle) {
            _ = try vkd.queueSubmit(self.transfer_queue, 1, @ptrCast(&submit_info), .null_handle);
            _ = try vkd.queueWaitIdle(self.transfer_queue);
        } else {
            _ = try vkd.queueSubmit(self.graphics_queue, 1, @ptrCast(&submit_info), .null_handle);
            _ = try vkd.queueWaitIdle(self.graphics_queue);
        }

        vkd.freeCommandBuffers(self.device, self.command_pool, 1, @ptrCast(&command_buffer));
    }

    fn copyBuffer(
        self: *HelloTriangleApplication,
        source_buffer: vk.Buffer,
        dest_buffer: vk.Buffer,
        size: vk.DeviceSize,
    ) !void {
        const command_buffer = try beginSingleTimeCommands(self);

        const copy_region = vk.BufferCopy{
            .src_offset = 0,
            .dst_offset = 0,
            .size = size,
        };

        vkd.cmdCopyBuffer(command_buffer, source_buffer, dest_buffer, 1, @ptrCast(&copy_region));

        try endSingleTimeCommands(self, command_buffer);
    }

    fn createBuffer(
        self: *HelloTriangleApplication,
        buffer_size: usize,
        usage: vk.BufferUsageFlags,
        properties: vk.MemoryPropertyFlags,
        buffer: *vk.Buffer,
        buffer_memory: *vk.DeviceMemory,
    ) !void {
        var buffer_info = vk.BufferCreateInfo{
            .size = buffer_size,
            .usage = usage,
            .sharing_mode = .exclusive,
            // TODO: modify sharing mode according to the queue family index
            //.sharing_mode = .concurrent,
        };

        buffer.* = try vkd.createBuffer(self.device, &buffer_info, null);
        const mem_requirements = vkd.getBufferMemoryRequirements(self.device, buffer.*);

        var alloc_info = vk.MemoryAllocateInfo{
            .allocation_size = mem_requirements.size,
            .memory_type_index = findMemoryType(self, mem_requirements.memory_type_bits, properties),
        };

        // NOTE: Offsets should be used appropriately in a production application instead of
        // allocating memory for every single buffer
        buffer_memory.* = try vkd.allocateMemory(self.device, &alloc_info, null);
        _ = try vkd.bindBufferMemory(self.device, buffer.*, buffer_memory.*, 0);
    }

    fn createIndexBuffer(self: *HelloTriangleApplication) !void {
        const buffer_size = @sizeOf(@TypeOf(self.indices.items[0])) * self.indices.items.len;

        var staging_buffer: vk.Buffer = .null_handle;
        var staging_buffer_memory: vk.DeviceMemory = .null_handle;

        try createBuffer(
            self,
            buffer_size,
            .{ .transfer_src_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
            &staging_buffer,
            &staging_buffer_memory,
        );

        const maybe_data = try vkd.mapMemory(self.device, staging_buffer_memory, 0, buffer_size, .{});

        if (maybe_data) |data| @memcpy(
            @as([*]u8, @ptrCast(data))[0..buffer_size],
            @as([*]u8, @ptrCast(self.indices.items.ptr)),
        );

        try createBuffer(
            self,
            buffer_size,
            .{ .transfer_dst_bit = true, .index_buffer_bit = true },
            .{ .device_local_bit = true },
            &self.index_buffer,
            &self.index_buffer_memory,
        );

        try copyBuffer(self, staging_buffer, self.index_buffer, buffer_size);

        vkd.destroyBuffer(self.device, staging_buffer, null);
        vkd.freeMemory(self.device, staging_buffer_memory, null);
    }

    fn createVertexBuffer(self: *HelloTriangleApplication) !void {
        const buffer_size = @sizeOf(Vertex) * self.vertices.items.len;

        var staging_buffer: vk.Buffer = .null_handle;
        var staging_buffer_memory: vk.DeviceMemory = .null_handle;

        try createBuffer(
            self,
            buffer_size,
            .{ .transfer_src_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
            &staging_buffer,
            &staging_buffer_memory,
        );

        const maybe_data = try vkd.mapMemory(self.device, staging_buffer_memory, 0, buffer_size, .{});

        if (maybe_data) |data| @memcpy(
            @as([*]u8, @ptrCast(data))[0..buffer_size],
            @as([*]u8, @ptrCast(self.vertices.items.ptr)),
        );

        try createBuffer(
            self,
            buffer_size,
            .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
            .{ .device_local_bit = true },
            &self.vertex_buffer,
            &self.vertex_buffer_memory,
        );

        try copyBuffer(self, staging_buffer, self.vertex_buffer, buffer_size);

        vkd.destroyBuffer(self.device, staging_buffer, null);
        vkd.freeMemory(self.device, staging_buffer_memory, null);
    }

    fn createSyncObjects(self: *HelloTriangleApplication) !void {
        self.image_available_semaphores = try allocator.alloc(vk.Semaphore, max_frames_in_flight);
        self.render_finished_semaphores = try allocator.alloc(vk.Semaphore, max_frames_in_flight);
        self.in_flight_fences = try allocator.alloc(vk.Fence, max_frames_in_flight);

        var semaphore_info = vk.SemaphoreCreateInfo{};

        var fence_info = vk.FenceCreateInfo{
            .flags = .{ .signaled_bit = true },
        };

        for (0..max_frames_in_flight) |i| {
            self.image_available_semaphores[i] = try vkd.createSemaphore(self.device, &semaphore_info, null);
            self.render_finished_semaphores[i] = try vkd.createSemaphore(self.device, &semaphore_info, null);
            self.in_flight_fences[i] = try vkd.createFence(self.device, &fence_info, null);
        }
    }

    fn recordCommandBuffer(
        self: *HelloTriangleApplication,
        command_buffer: vk.CommandBuffer,
        image_index: u32,
    ) !void {
        var begin_info = vk.CommandBufferBeginInfo{
            .flags = .{},
            .p_inheritance_info = null,
        };

        _ = try vkd.beginCommandBuffer(command_buffer, &begin_info);

        const clear_values = [_]vk.ClearValue{
            .{
                .color = .{ .float_32 = .{ 0, 0, 0, 1 } },
            },
            .{
                .depth_stencil = .{ .depth = 1, .stencil = 0 },
            },
        };

        var render_pass_info = vk.RenderPassBeginInfo{
            .render_pass = self.render_pass,
            .framebuffer = self.swap_chain_framebuffers[image_index],
            .render_area = .{ .offset = .{ .x = 0, .y = 0 }, .extent = self.swap_chain_extent },
            .clear_value_count = clear_values.len,
            .p_clear_values = &clear_values,
        };

        vkd.cmdBeginRenderPass(command_buffer, &render_pass_info, .@"inline");
        vkd.cmdBindPipeline(command_buffer, .graphics, self.graphics_pipeline);

        const vertex_buffers = [_]vk.Buffer{self.vertex_buffer};
        const offsets = [_]vk.DeviceSize{0};
        vkd.cmdBindVertexBuffers(command_buffer, 0, 1, &vertex_buffers, &offsets);
        vkd.cmdBindIndexBuffer(command_buffer, self.index_buffer, 0, .uint32);

        const viewport = vk.Viewport{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(self.swap_chain_extent.width),
            .height = @floatFromInt(self.swap_chain_extent.height),
            .min_depth = 0,
            .max_depth = 1,
        };

        vkd.cmdSetViewport(command_buffer, 0, 1, @ptrCast(&viewport));

        const scissor = vk.Rect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swap_chain_extent,
        };

        vkd.cmdSetScissor(command_buffer, 0, 1, @ptrCast(&scissor));

        vkd.cmdBindDescriptorSets(
            command_buffer,
            .graphics,
            self.pipeline_layout,
            0,
            1,
            @ptrCast(&self.descriptor_sets[current_frame]),
            0,
            null,
        );

        vkd.cmdDrawIndexed(command_buffer, @intCast(self.indices.items.len), 1, 0, 0, 0);
        vkd.cmdEndRenderPass(command_buffer);
        _ = try vkd.endCommandBuffer(command_buffer);
    }

    fn createCommandBuffers(self: *HelloTriangleApplication) !void {
        self.command_buffers = try allocator.alloc(vk.CommandBuffer, max_frames_in_flight);

        var alloc_info = vk.CommandBufferAllocateInfo{
            .command_pool = self.command_pool,
            .level = .primary,
            .command_buffer_count = @intCast(self.command_buffers.len),
        };

        _ = try vkd.allocateCommandBuffers(self.device, &alloc_info, self.command_buffers.ptr);
    }

    fn createCommandPool(self: *HelloTriangleApplication) !void {
        const queue_family_indices = try findQueueFamilies(self, self.physical_device);

        var pool_info = vk.CommandPoolCreateInfo{
            .flags = .{ .reset_command_buffer_bit = true },
            .queue_family_index = queue_family_indices.graphics_family.?,
        };

        self.command_pool = try vkd.createCommandPool(self.device, &pool_info, null);

        if (queue_family_indices.transfer_family) |transfer_family| {
            pool_info = vk.CommandPoolCreateInfo{
                .flags = .{ .reset_command_buffer_bit = true },
                .queue_family_index = transfer_family,
            };

            self.transfer_command_pool = try vkd.createCommandPool(self.device, &pool_info, null);
        }
    }

    fn createFramebuffers(self: *HelloTriangleApplication) !void {
        self.swap_chain_framebuffers = try allocator.alloc(vk.Framebuffer, self.swap_chain_image_views.len);

        for (self.swap_chain_image_views, self.swap_chain_framebuffers) |image_view, *framebuffer| {
            const attachments = [_]vk.ImageView{
                self.color_image_view,
                self.depth_image_view,
                image_view,
            };

            const framebuffer_info = vk.FramebufferCreateInfo{
                .render_pass = self.render_pass,
                .attachment_count = attachments.len,
                .p_attachments = &attachments,
                .width = self.swap_chain_extent.width,
                .height = self.swap_chain_extent.height,
                .layers = 1,
            };

            framebuffer.* = try vkd.createFramebuffer(self.device, &framebuffer_info, null);
        }
    }

    fn createRenderPass(self: *HelloTriangleApplication) !void {
        const color_attachment = vk.AttachmentDescription{
            .format = self.swap_chain_image_format,
            .samples = self.msaa_samples,
            .load_op = .clear,
            .store_op = .store,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .undefined,
            .final_layout = .color_attachment_optimal,
        };

        const depth_attachment = vk.AttachmentDescription{
            .format = findDepthFormat(self),
            .samples = self.msaa_samples,
            .load_op = .clear,
            .store_op = .dont_care,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .undefined,
            .final_layout = .depth_stencil_attachment_optimal,
        };

        const color_resolve_attachment = vk.AttachmentDescription{
            .format = self.swap_chain_image_format,
            .samples = .{ .@"1_bit" = true },
            .load_op = .dont_care,
            .store_op = .store,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .undefined,
            .final_layout = .present_src_khr,
        };

        const color_attachment_ref = vk.AttachmentReference{
            .attachment = 0,
            .layout = .color_attachment_optimal,
        };

        const depth_attachment_ref = vk.AttachmentReference{
            .attachment = 1,
            .layout = .depth_stencil_attachment_optimal,
        };

        const color_resolve_attachment_ref = vk.AttachmentReference{
            .attachment = 2,
            .layout = .color_attachment_optimal,
        };

        const subpass = vk.SubpassDescription{
            .pipeline_bind_point = .graphics,
            .color_attachment_count = 1,
            .p_color_attachments = &.{color_attachment_ref},
            .p_depth_stencil_attachment = &depth_attachment_ref,
            .p_resolve_attachments = &.{color_resolve_attachment_ref},
        };

        const dependency = vk.SubpassDependency{
            .src_subpass = vk.SUBPASS_EXTERNAL,
            .dst_subpass = 0,
            .src_stage_mask = .{ .color_attachment_output_bit = true, .early_fragment_tests_bit = true },
            .src_access_mask = .{},
            .dst_stage_mask = .{ .color_attachment_output_bit = true, .early_fragment_tests_bit = true },
            .dst_access_mask = .{ .color_attachment_write_bit = true, .depth_stencil_attachment_write_bit = true },
        };

        const attachments = [_]vk.AttachmentDescription{
            color_attachment,
            depth_attachment,
            color_resolve_attachment,
        };

        const render_pass_info = vk.RenderPassCreateInfo{
            .attachment_count = attachments.len,
            .p_attachments = &attachments,
            .subpass_count = 1,
            .p_subpasses = &.{subpass},
            .dependency_count = 1,
            .p_dependencies = @ptrCast(&dependency),
        };

        self.render_pass = try vkd.createRenderPass(self.device, &render_pass_info, null);
    }

    fn createGraphicsPipeline(self: *HelloTriangleApplication) !void {
        //const vert_shader_module = try createShaderModule(self, vert);
        const vert_shader_module = try vkd.createShaderModule(self.device, &.{
            .code_size = vert.len,
            .p_code = @ptrCast(@alignCast(vert)),
        }, null);
        defer vkd.destroyShaderModule(self.device, vert_shader_module, null);

        //const frag_shader_module = try createShaderModule(self, frag);
        const frag_shader_module = try vkd.createShaderModule(self.device, &.{
            .code_size = frag.len,
            .p_code = @ptrCast(@alignCast(frag)),
        }, null);
        defer vkd.destroyShaderModule(self.device, frag_shader_module, null);

        const vert_shader_stage_info = vk.PipelineShaderStageCreateInfo{
            .stage = .{ .vertex_bit = true },
            .module = vert_shader_module,
            .p_name = "main",
        };

        const frag_shader_stage_info = vk.PipelineShaderStageCreateInfo{
            .stage = .{ .fragment_bit = true },
            .module = frag_shader_module,
            .p_name = "main",
        };

        const shader_stages = [_]vk.PipelineShaderStageCreateInfo{ vert_shader_stage_info, frag_shader_stage_info };

        const dynamic_states = [_]vk.DynamicState{ .viewport, .scissor };
        const dynamic_state = vk.PipelineDynamicStateCreateInfo{
            .dynamic_state_count = dynamic_states.len,
            .p_dynamic_states = &dynamic_states,
        };

        const binding_description = Vertex.getBindingDescription();
        const attribute_descriptions = try Vertex.getAttributeDescriptions();
        defer allocator.free(attribute_descriptions);

        const vertex_input_info = vk.PipelineVertexInputStateCreateInfo{
            .vertex_binding_description_count = 1,
            .p_vertex_binding_descriptions = @ptrCast(&binding_description),
            .vertex_attribute_description_count = @intCast(attribute_descriptions.len),
            .p_vertex_attribute_descriptions = attribute_descriptions.ptr,
        };

        const input_assembly = vk.PipelineInputAssemblyStateCreateInfo{
            .topology = .triangle_list,
            .primitive_restart_enable = vk.FALSE,
        };

        const viewport = vk.Viewport{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(self.swap_chain_extent.width),
            .height = @floatFromInt(self.swap_chain_extent.height),
            .min_depth = 0,
            .max_depth = 1,
        };

        const scissor = vk.Rect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swap_chain_extent,
        };

        const viewport_state = vk.PipelineViewportStateCreateInfo{
            .viewport_count = 1,
            .p_viewports = &.{viewport},
            .scissor_count = 1,
            .p_scissors = &.{scissor},
        };

        const rasterizer = vk.PipelineRasterizationStateCreateInfo{
            .depth_clamp_enable = vk.FALSE,
            .rasterizer_discard_enable = vk.FALSE,
            .polygon_mode = .fill,
            .line_width = 1,
            .cull_mode = .{ .back_bit = true },
            .front_face = .counter_clockwise,
            .depth_bias_enable = vk.FALSE,
            .depth_bias_constant_factor = 0,
            .depth_bias_clamp = 0,
            .depth_bias_slope_factor = 0,
        };

        const multisampling = vk.PipelineMultisampleStateCreateInfo{
            .sample_shading_enable = vk.TRUE,
            .rasterization_samples = self.msaa_samples,
            .min_sample_shading = 0.2,
            .p_sample_mask = null,
            .alpha_to_coverage_enable = vk.FALSE,
            .alpha_to_one_enable = vk.FALSE,
        };

        const color_blend_attachment = vk.PipelineColorBlendAttachmentState{
            .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
            //.blend_enable = vk.FALSE,
            //.src_color_blend_factor = .one,
            //.dst_color_blend_factor = .zero,
            .blend_enable = vk.TRUE,
            .src_color_blend_factor = .src_alpha,
            .dst_color_blend_factor = .one_minus_src_alpha,
            .color_blend_op = .add,
            .src_alpha_blend_factor = .one,
            .dst_alpha_blend_factor = .zero,
            .alpha_blend_op = .add,
        };

        const color_blending = vk.PipelineColorBlendStateCreateInfo{
            .logic_op_enable = vk.FALSE,
            .logic_op = .copy,
            .attachment_count = 1,
            .p_attachments = &.{color_blend_attachment},
            .blend_constants = .{ 0, 0, 0, 0 },
        };

        const pipeline_layout_info = vk.PipelineLayoutCreateInfo{
            .set_layout_count = 1,
            .p_set_layouts = @ptrCast(&self.descriptor_set_layout),
            .push_constant_range_count = 0,
            .p_push_constant_ranges = null,
        };

        self.pipeline_layout = try vkd.createPipelineLayout(self.device, &pipeline_layout_info, null);

        const depth_stencil = vk.PipelineDepthStencilStateCreateInfo{
            .depth_test_enable = vk.TRUE,
            .depth_write_enable = vk.TRUE,
            .depth_compare_op = .less,
            .depth_bounds_test_enable = vk.FALSE,
            .min_depth_bounds = 0,
            .max_depth_bounds = 0,
            .stencil_test_enable = vk.FALSE,
            .front = .{
                .fail_op = .zero,
                .pass_op = .zero,
                .depth_fail_op = .zero,
                .compare_op = .never,
                .write_mask = 0,
                .compare_mask = 0,
                .reference = 0,
            },
            .back = .{
                .fail_op = .zero,
                .pass_op = .zero,
                .depth_fail_op = .zero,
                .compare_op = .never,
                .write_mask = 0,
                .compare_mask = 0,
                .reference = 0,
            },
        };

        const pipeline_info = vk.GraphicsPipelineCreateInfo{
            .stage_count = 2,
            .p_stages = &shader_stages,
            .p_vertex_input_state = &vertex_input_info,
            .p_input_assembly_state = &input_assembly,
            .p_viewport_state = &viewport_state,
            .p_rasterization_state = &rasterizer,
            .p_multisample_state = &multisampling,
            .p_depth_stencil_state = &depth_stencil,
            .p_color_blend_state = &color_blending,
            .p_dynamic_state = &dynamic_state,
            .layout = self.pipeline_layout,
            .render_pass = self.render_pass,
            .subpass = 0,
            .base_pipeline_handle = .null_handle,
            .base_pipeline_index = 1,
        };

        _ = try vkd.createGraphicsPipelines(
            self.device,
            .null_handle,
            1,
            &.{pipeline_info},
            null,
            @ptrCast(&self.graphics_pipeline),
        );
    }

    // NOTE: For some reason, use of this function produces an incorrect alignment error
    // Is the implicit conversion to []const u8 somehow improper?
    fn createShaderModule(self: *HelloTriangleApplication, code: []const u8) !vk.ShaderModule {
        var create_info = vk.ShaderModuleCreateInfo{
            .code_size = code.len,
            .p_code = @ptrCast(@alignCast(code)),
        };

        const result = try vkd.createShaderModule(self.device, &create_info, null);

        return result;
    }

    fn createImageViews(self: *HelloTriangleApplication) !void {
        self.swap_chain_image_views = try allocator.alloc(vk.ImageView, self.swap_chain_images.len);

        for (self.swap_chain_images, self.swap_chain_image_views) |image, *image_view| {
            image_view.* = try createImageView(self, image, self.swap_chain_image_format, .{ .color_bit = true }, 1);
        }
    }

    fn createSwapChain(self: *HelloTriangleApplication, window: glfw.Window, old_swapchain: vk.SwapchainKHR) !void {
        const swap_chain_support = try querySwapChainSupport(self, self.physical_device);
        const surface_format = chooseSwapSurfaceFormat(swap_chain_support.formats);
        const present_mode = chooseSwapPresentMode(swap_chain_support.present_modes);
        const extent = chooseSwapExtent(window, &swap_chain_support.capabilities);
        var image_count = swap_chain_support.capabilities.min_image_count + 1;

        if (swap_chain_support.capabilities.max_image_count > 0 and
            image_count > swap_chain_support.capabilities.max_image_count)
        {
            image_count = swap_chain_support.capabilities.max_image_count;
        }

        var create_info = vk.SwapchainCreateInfoKHR{
            .surface = self.surface,
            .min_image_count = image_count,
            .image_format = surface_format.format,
            .image_color_space = surface_format.color_space,
            .image_extent = extent,
            .image_array_layers = 1,
            .image_usage = .{ .color_attachment_bit = true },
            .image_sharing_mode = .exclusive,
            .pre_transform = swap_chain_support.capabilities.current_transform,
            .composite_alpha = .{ .opaque_bit_khr = true },
            .present_mode = present_mode,
            .clipped = vk.TRUE,
            .old_swapchain = old_swapchain,
        };

        const queue_family_indices = try findQueueFamilies(self, self.physical_device);
        defer allocator.free(queue_family_indices.slice);

        if (queue_family_indices.graphics_family.? != queue_family_indices.present_family.?) {
            create_info.image_sharing_mode = .concurrent;
            create_info.queue_family_index_count = @intCast(queue_family_indices.slice.len);
            create_info.p_queue_family_indices = queue_family_indices.slice.ptr;
        } else {
            create_info.image_sharing_mode = .exclusive;
            create_info.queue_family_index_count = 0;
            create_info.p_queue_family_indices = null;
        }

        self.swap_chain = try vkd.createSwapchainKHR(self.device, &create_info, null);
        _ = try vkd.getSwapchainImagesKHR(self.device, self.swap_chain, &image_count, null);
        self.swap_chain_images = try allocator.alloc(vk.Image, image_count);
        _ = try vkd.getSwapchainImagesKHR(self.device, self.swap_chain, &image_count, self.swap_chain_images.ptr);
        self.swap_chain_image_format = surface_format.format;
        self.swap_chain_extent = extent;
    }

    fn cleanupSwapChain(self: *HelloTriangleApplication, old_swapchain: vk.SwapchainKHR) !void {
        vkd.destroyImageView(self.device, self.color_image_view, null);
        vkd.destroyImage(self.device, self.color_image, null);
        vkd.freeMemory(self.device, self.color_image_memory, null);

        vkd.destroyImageView(self.device, self.depth_image_view, null);
        vkd.destroyImage(self.device, self.depth_image, null);
        vkd.freeMemory(self.device, self.depth_image_memory, null);

        for (self.swap_chain_framebuffers) |framebuffer| {
            vkd.destroyFramebuffer(self.device, framebuffer, null);
        }

        for (self.swap_chain_image_views) |image_view| {
            vkd.destroyImageView(self.device, image_view, null);
        }

        vkd.destroySwapchainKHR(self.device, old_swapchain, null);
    }

    fn recreateSwapChain(self: *HelloTriangleApplication, window: glfw.Window) !void {
        var size = window.getFramebufferSize();

        while (size.width == 0 or size.height == 0) {
            size = window.getFramebufferSize();
            glfw.waitEvents();
        }

        try vkd.deviceWaitIdle(self.device);
        const old_swapchain = self.swap_chain;
        try createSwapChain(self, window, old_swapchain);
        try cleanupSwapChain(self, old_swapchain);
        try createImageViews(self);
        try createColorResources(self);
        try createDepthResources(self);
        try createFramebuffers(self);
    }

    fn createSurface(self: *HelloTriangleApplication, window: glfw.Window) !void {
        if (glfw.createWindowSurface(
            self.instance,
            window,
            null,
            &self.surface,
        ) != @intFromEnum(vk.Result.success)) {
            @panic("failed to create window surface!");
        }
    }

    fn createLogicalDevice(self: *HelloTriangleApplication) !void {
        const queue_family_indices = try findQueueFamilies(self, self.physical_device);
        defer allocator.free(queue_family_indices.slice);

        var queue_create_infos = try allocator.alloc(vk.DeviceQueueCreateInfo, queue_family_indices.slice.len);
        defer allocator.free(queue_create_infos);
        const queue_priority: [1]f32 = .{1};

        for (queue_family_indices.slice, 0..) |queue_family, i| {
            queue_create_infos.ptr[i] = .{
                .queue_family_index = queue_family,
                .queue_count = 1,
                .p_queue_priorities = &queue_priority,
            };
        }

        const device_features: vk.PhysicalDeviceFeatures = .{
            .sampler_anisotropy = vk.TRUE,
            .sample_rate_shading = vk.TRUE,
        };

        var create_info: vk.DeviceCreateInfo = .{
            .queue_create_info_count = @intCast(queue_create_infos.len),
            .p_queue_create_infos = queue_create_infos.ptr,
            .p_enabled_features = &device_features,
            .enabled_extension_count = device_extensions.len,
            .pp_enabled_extension_names = &device_extensions,
        };

        var layers = try std.ArrayList([*:0]const u8)
            .initCapacity(allocator, validation_layers.len + 2);
        defer layers.deinit();

        // NOTE: It seems that even though pp_enabled_layer_names is deprecated for devices,
        // a Validation Error is produced with or without appending the portability
        // extensions here. The same error still presents without the portability extensions
        // appended, but then the deprecation message goes away. Maybe this Validation Error
        // shows erroneously with 1.3.283 but the portability extensions would be required
        // for backwards compatibility
        //
        // loader_create_device_chain: Using deprecated and ignored 'ppEnabledLayerNames' member of 'VkDeviceCreateInfo' when creating a Vulkan device.
        // Validation Error: [ VUID-VkDeviceCreateInfo-pProperties-04451 ] Object ... vkCreateDevice():
        // VK_KHR_portability_subset must be enabled because physical device VkPhysicalDevice 0x60000269b5a0[] supports it. The Vulkan spec states:
        // If the VK_KHR_portability_subset extension is included in pProperties of vkEnumerateDeviceExtensionProperties,
        // ppEnabledExtensionNames must include "VK_KHR_portability_subset"
        if (builtin.os.tag == .macos) {
            try layers.append(@ptrCast(
                vk.extensions.khr_portability_subset.name,
            ));
            try layers.append(@ptrCast(
                vk.extensions.khr_portability_enumeration.name,
            ));
        }

        if (enable_validation_layers) {
            // NOTE: pp_enabled_layer names are inherited and therefore deprecated
            //create_info.enabled_layer_count = @intCast(layers.items.len);
            //create_info.pp_enabled_layer_names = @ptrCast(layers.items);
        } else {
            create_info.enabled_layer_count = 0;
        }

        self.device = try vki.createDevice(self.physical_device, &create_info, null);
        vkd = try DeviceDispatch.load(self.device, vki.dispatch.vkGetDeviceProcAddr);

        self.graphics_queue = vkd.getDeviceQueue(self.device, queue_family_indices.graphics_family.?, 0);
        self.present_queue = vkd.getDeviceQueue(self.device, queue_family_indices.present_family.?, 0);

        if (queue_family_indices.transfer_family) |transfer_family| {
            self.transfer_queue = vkd.getDeviceQueue(self.device, transfer_family, 0);
        }
    }

    fn pickPhysicalDevice(self: *HelloTriangleApplication) !void {
        var device_count: u32 = undefined;

        _ = try vki.enumeratePhysicalDevices(self.instance, &device_count, null);

        if (device_count == 0) @panic("failed to find GPUs with Vulkan support!");

        const devices = try allocator.alloc(vk.PhysicalDevice, device_count);
        defer allocator.free(devices);

        _ = try vki.enumeratePhysicalDevices(self.instance, &device_count, devices.ptr);

        var candidates = std.AutoHashMap(vk.PhysicalDevice, i32).init(allocator);
        defer candidates.deinit();

        for (devices) |device| {
            const score = rateDeviceSuitability(device);
            try candidates.put(device, score);
        }

        var it = candidates.iterator();
        var best_score: i32 = 0;
        while (it.next()) |device| {
            if (device.value_ptr.* > best_score) {
                // TODO: This check should be baked into rateDeviceSuitability()
                if (try deviceIsSuitable(self, device.key_ptr.*)) {
                    best_score = device.value_ptr.*;

                    self.physical_device = device.key_ptr.*;
                }
            }
        }

        self.msaa_samples = getMaxUsableSampleCount(self);

        if (self.physical_device == .null_handle) {
            @panic("failed to find suitable GPU!");
        }
    }

    fn deviceIsSuitable(self: *HelloTriangleApplication, device: vk.PhysicalDevice) !bool {
        const queue_family_indices = try findQueueFamilies(self, device);
        defer allocator.free(queue_family_indices.slice);

        const extensions_supported = try checkDeviceExtensionSupport(device);

        var swap_chain_adequate = false;

        if (extensions_supported) {
            const swap_chain_support = try querySwapChainSupport(self, device);
            defer allocator.free(swap_chain_support.formats);
            defer allocator.free(swap_chain_support.present_modes);
            swap_chain_adequate = swap_chain_support.formats.len > 0 and
                swap_chain_support.present_modes.len > 0;
        }

        const supported_features = vki.getPhysicalDeviceFeatures(device);

        return queue_family_indices.graphics_family != null and
            queue_family_indices.present_family != null and
            extensions_supported and
            swap_chain_adequate and
            supported_features.sampler_anisotropy == vk.TRUE;
    }

    fn checkDeviceExtensionSupport(device: vk.PhysicalDevice) !bool {
        var result = true;

        var extension_count: u32 = undefined;
        _ = try vki.enumerateDeviceExtensionProperties(device, null, &extension_count, null);
        const available_extensions = try allocator.alloc(vk.ExtensionProperties, extension_count);
        defer allocator.free(available_extensions);
        _ = try vki.enumerateDeviceExtensionProperties(device, null, &extension_count, available_extensions.ptr);

        for (device_extensions) |required_extension| {
            var extension_is_available = false;

            for (available_extensions) |available_extension| {
                const len = std.mem.indexOfScalar(u8, &available_extension.extension_name, 0).?;
                const extension_name = available_extension.extension_name[0..len];

                if (std.mem.eql(u8, extension_name, std.mem.span(required_extension))) {
                    extension_is_available = true;
                    break;
                }
            }

            if (!extension_is_available) {
                result = false;
                break;
            }
        }

        return result;
    }

    fn findQueueFamilies(self: *HelloTriangleApplication, device: vk.PhysicalDevice) !QueueFamilyIndices {
        var queue_family_indices: QueueFamilyIndices = .{};

        var queue_family_count: u32 = undefined;
        vki.getPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);

        const queue_families = try allocator.alloc(vk.QueueFamilyProperties, queue_family_count);
        defer allocator.free(queue_families);

        vki.getPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_families.ptr);

        var i: u32 = 0;
        for (queue_families) |family| {
            if (family.queue_flags.graphics_bit) {
                queue_family_indices.graphics_family = i;
            }

            // NOTE: No queue families on my laptop have the transfer bit without the graphics bit
            if (!family.queue_flags.graphics_bit and family.queue_flags.transfer_bit) {
                queue_family_indices.transfer_family = i;
            }

            const present_support = try vki.getPhysicalDeviceSurfaceSupportKHR(device, i, self.surface);

            if (present_support == vk.TRUE) {
                queue_family_indices.present_family = i;
            }

            if (queue_family_indices.graphics_family != null and
                queue_family_indices.present_family != null)
            {
                break;
            }

            i += 1;
        }

        // NOTE: It appears that in newer versions of Vulkan, using the same queue family index across
        // multiple create infos would be regarded as bad practice, and the following Validation Error(s)
        // are produced when doing so to point this out:
        // ADDENDUM: Using the same index multiple times causes the app to fail altogether outside of
        // macos (MoltenVK), confirming the above
        //
        // Validation Error: [ VUID-VkDeviceCreateInfo-queueFamilyIndex-02802 ] Object 0: handle = 0x6000026d5880, type = VK_OBJECT_TYPE_PHYSICAL_DEVICE;
        //      | MessageID = 0x29498778 | vkCreateDevice(): pCreateInfo->pQueueCreateInfos[1].queueFamilyIndex (0) is not unique and was also used in
        //      pCreateInfo->pQueueCreateInfos[0]. The Vulkan spec states: The queueFamilyIndex member of each element of pQueueCreateInfos must be unique
        //      within pQueueCreateInfos , except that two members can share the same queueFamilyIndex if one describes protected-capable queues and one
        //      describes queues that are not protected-capable
        //      (https://vulkan.lunarg.com/doc/view/1.3.283.0/mac/1.3-extensions/vkspec.html#VUID-VkDeviceCreateInfo-queueFamilyIndex-02802)
        //
        // Validation Error: [ VUID-VkDeviceCreateInfo-pQueueCreateInfos-06755 ] Object 0: handle = 0x6000026d5880, type = VK_OBJECT_TYPE_PHYSICAL_DEVICE;
        //      | MessageID = 0x4180bcf6 | vkCreateDevice(): pCreateInfo Total queue count requested from queue family index 0 is 2, which is greater than
        //      queue count available in the queue family (1). The Vulkan spec states: If multiple elements of pQueueCreateInfos share the same queueFamilyIndex,
        //      the sum of their queueCount members must be less than or equal to the queueCount member of the VkQueueFamilyProperties structure, as returned
        //      by vkGetPhysicalDeviceQueueFamilyProperties in the pQueueFamilyProperties[queueFamilyIndex]
        //      (https://vulkan.lunarg.com/doc/view/1.3.283.0/mac/1.3-extensions/vkspec.html#VUID-VkDeviceCreateInfo-pQueueCreateInfos-06755)
        //
        // Here we store a slice of one or more unique indices for later use, ensuring we do not encounter
        // the above validation errors
        // TODO: This conditional is now a bit convoluted, can it be cleaned up?
        if (queue_family_indices.graphics_family) |graphics_family| {
            if (queue_family_indices.present_family) |present_family| {
                if (queue_family_indices.transfer_family) |transfer_family| {
                    if (graphics_family == present_family) {
                        queue_family_indices.slice = try allocator.alloc(u32, 2);
                        queue_family_indices.slice[0] = graphics_family;
                        queue_family_indices.slice[1] = transfer_family;
                    } else if (transfer_family == present_family) {
                        queue_family_indices.slice = try allocator.alloc(u32, 2);
                        queue_family_indices.slice[0] = graphics_family;
                        queue_family_indices.slice[1] = transfer_family;
                    } else {
                        queue_family_indices.slice = try allocator.alloc(u32, 3);
                        queue_family_indices.slice[0] = graphics_family;
                        queue_family_indices.slice[1] = present_family;
                        queue_family_indices.slice[2] = transfer_family;
                    }
                } else {
                    if (graphics_family == present_family) {
                        queue_family_indices.slice = try allocator.alloc(u32, 1);
                        queue_family_indices.slice[0] = graphics_family;
                    } else {
                        queue_family_indices.slice = try allocator.alloc(u32, 2);
                        queue_family_indices.slice[0] = graphics_family;
                        queue_family_indices.slice[1] = present_family;
                    }
                }
            } else unreachable;
        } else unreachable;

        return queue_family_indices;
    }

    fn rateDeviceSuitability(device: vk.PhysicalDevice) i32 {
        var result: i32 = 0;

        const device_props = vki.getPhysicalDeviceProperties(device);
        const device_features = vki.getPhysicalDeviceFeatures(device);

        if (device_props.device_type == .discrete_gpu) {
            result += 1000;
        }

        result += @intCast(device_props.limits.max_image_dimension_2d);

        // NOTE: My laptop does not support geometry shaders
        // if (device_features.geometry_shader != vk.TRUE) {
        if (device_features.tessellation_shader != vk.TRUE) {
            result = 0;
        }

        return result;
    }

    fn vkDebugUtilsMessengerCreateInfo() vk.DebugUtilsMessengerCreateInfoEXT {
        const result: vk.DebugUtilsMessengerCreateInfoEXT = .{
            .message_severity = vk.DebugUtilsMessageSeverityFlagsEXT{
                .verbose_bit_ext = true,
                .warning_bit_ext = true,
                .error_bit_ext = true,
            },
            .message_type = vk.DebugUtilsMessageTypeFlagsEXT{
                .general_bit_ext = true,
                .validation_bit_ext = true,
                .performance_bit_ext = true,
            },
            .pfn_user_callback = debugCallback,
        };

        return result;
    }

    fn setupDebugMessenger(self: *HelloTriangleApplication) void {
        if (enable_validation_layers) {
            const create_info = vkDebugUtilsMessengerCreateInfo();

            if (try createDebugUtilsMessengerEXT(
                self.instance,
                &create_info,
                null,
                &self.debug_messenger,
            ) != .success) {
                @panic("failed to set up debug messenger!");
            }
        }
    }

    fn createInstance(self: *HelloTriangleApplication) !void {
        vkb = try BaseDispatch.load(@as(
            vk.PfnGetInstanceProcAddr,
            @ptrCast(&glfw.getInstanceProcAddress),
        ));

        const instance_extensions = try getRequiredExtensions();
        defer instance_extensions.deinit();

        // TODO: Improve the clarity of this conditional
        if (enable_validation_layers and !(try checkValidationLayerSupport())) {
            @panic("validation layers requested, but not available!");
        }

        const app_info = vk.ApplicationInfo{
            .p_application_name = "Hello Triangle",
            .application_version = vk.makeApiVersion(0, 0, 0, 0),
            .p_engine_name = "No Engine",
            .engine_version = vk.makeApiVersion(0, 0, 0, 0),
            .api_version = vk.makeApiVersion(0, 1, 3, 0),
        };

        var create_info = vk.InstanceCreateInfo{
            .flags = if (builtin.os.tag == .macos) .{
                .enumerate_portability_bit_khr = true,
            } else .{},
            .p_application_info = &app_info,
            .enabled_extension_count = @intCast(instance_extensions.items.len),
            .pp_enabled_extension_names = @ptrCast(instance_extensions.items),
        };

        var debug_create_info = vkDebugUtilsMessengerCreateInfo();
        if (enable_validation_layers) {
            create_info.enabled_layer_count = validation_layers.len;
            create_info.pp_enabled_layer_names = &validation_layers;
            create_info.p_next = &debug_create_info;
        } else {
            create_info.enabled_layer_count = 0;
            create_info.pp_enabled_layer_names = null;
            create_info.p_next = null;
        }

        self.instance = try vkb.createInstance(&create_info, null);
        errdefer vki.destroyInstance(self.instance, null);

        vki = try InstanceDispatch.load(self.instance, vkb.dispatch.vkGetInstanceProcAddr);
    }

    fn mainLoop(self: *HelloTriangleApplication, window: glfw.Window) !void {
        while (!window.shouldClose()) {
            glfw.pollEvents();
            // TODO: Figure out why calling drawFrame() on the pointer itself causes a seg fault
            try drawFrame(self, window);
        }

        try vkd.deviceWaitIdle(self.device);
    }

    fn drawFrame(self: *HelloTriangleApplication, window: glfw.Window) !void {
        _ = try vkd.waitForFences(self.device, 1, @ptrCast(&self.in_flight_fences[current_frame]), vk.TRUE, std.math.maxInt(u64));

        const image_result = try vkd.acquireNextImageKHR(
            self.device,
            self.swap_chain,
            std.math.maxInt(u64),
            self.image_available_semaphores[current_frame],
            .null_handle,
        );

        if (image_result.result == .error_out_of_date_khr) {
            try recreateSwapChain(self, window);
            return;
        } else if (image_result.result != .success and image_result.result != .suboptimal_khr) {
            @panic("failed to acquire swap chain image!");
        }

        _ = try vkd.resetFences(self.device, 1, @ptrCast(&self.in_flight_fences[current_frame]));
        _ = try vkd.resetCommandBuffer(self.command_buffers[current_frame], .{});
        _ = try recordCommandBuffer(self, self.command_buffers[current_frame], image_result.image_index);

        try updateUniformBuffer(self, current_frame);

        const wait_semaphores = [_]vk.Semaphore{self.image_available_semaphores[current_frame]};
        const wait_stages = [_]vk.PipelineStageFlags{.{ .color_attachment_output_bit = true }};
        const signal_semaphores = [_]vk.Semaphore{self.render_finished_semaphores[current_frame]};

        var submit_info = vk.SubmitInfo{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = &wait_semaphores,
            .p_wait_dst_stage_mask = &wait_stages,
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&self.command_buffers[current_frame]),
            .signal_semaphore_count = 1,
            .p_signal_semaphores = &signal_semaphores,
        };

        try vkd.queueSubmit(self.graphics_queue, 1, @ptrCast(&submit_info), self.in_flight_fences[current_frame]);

        const swap_chains = [_]vk.SwapchainKHR{self.swap_chain};
        const present_info = vk.PresentInfoKHR{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = &signal_semaphores,
            .swapchain_count = 1,
            .p_swapchains = &swap_chains,
            .p_image_indices = @ptrCast(&image_result.image_index),
            .p_results = null,
        };

        const present_result = try vkd.queuePresentKHR(self.present_queue, &present_info);

        if (present_result == .error_out_of_date_khr or
            present_result == .suboptimal_khr or
            self.framebuffer_resized)
        {
            self.framebuffer_resized = false;
            try recreateSwapChain(self, window);
        } else if (present_result != .success) {
            @panic("failed to present swap chain image");
        }

        current_frame = (current_frame + 1) % max_frames_in_flight;
    }

    fn updateUniformBuffer(self: *HelloTriangleApplication, current_image: u32) !void {
        const time = self.timer.read() / std.time.ns_per_s;

        // model
        const model = Mat4x4.rotateZ(@as(f32, @floatFromInt(time)) * std.math.pi / 2);

        // view matrix
        const eye = Vec3.splat(1);
        const center = Vec3.splat(0);
        const up = vec3(0, 0, 1);

        const f = Vec3.normalize(&Vec3.sub(&center, &eye), 0);
        var u = Vec3.normalize(&up, 0);
        const s = Vec3.normalize(&Vec3.cross(&f, &u), 0);
        u = Vec3.cross(&s, &f);

        var view = Mat4x4.ident;
        view.v[0].v[0] = s.x();
        view.v[1].v[0] = s.y();
        view.v[2].v[0] = s.z();
        view.v[0].v[1] = u.x();
        view.v[1].v[1] = u.y();
        view.v[2].v[1] = u.z();
        view.v[0].v[2] = -f.x();
        view.v[1].v[2] = -f.y();
        view.v[2].v[2] = -f.z();
        view.v[3].v[0] = -Vec3.dot(&s, &eye);
        view.v[3].v[1] = -Vec3.dot(&u, &eye);
        view.v[3].v[2] = Vec3.dot(&f, &eye);

        // projection matrix
        const angle: f32 = std.math.pi / 2.0;
        const aspect: f32 =
            @as(f32, @floatFromInt(self.swap_chain_extent.width)) /
            @as(f32, @floatFromInt(self.swap_chain_extent.height));
        const near = 0.1;
        const far = 10.0;

        const zero = Vec4.splat(0);
        var proj = Mat4x4.init(&zero, &zero, &zero, &zero);
        const tan_half_angle = @tan(angle / 2);
        proj.v[0].v[0] = 1 / (aspect * tan_half_angle);
        proj.v[1].v[1] = 1 / (tan_half_angle);
        proj.v[2].v[2] = far / (near - far);
        proj.v[2].v[3] = -1;
        proj.v[3].v[2] = -(far * near) / (far - near);

        var ubo = UniformBufferObject{
            .model = model,
            .view = view,
            .proj = proj,
        };

        ubo.proj.v[1].v[1] *= -1;

        if (self.uniform_buffers_mapped[current_image]) |data| {
            @memcpy(
                @as([*]u8, @ptrCast(data))[0..@sizeOf(UniformBufferObject)],
                @as([*]u8, @ptrCast(&ubo)),
            );
        }
    }

    fn cleanup(self: *HelloTriangleApplication) void {
        try cleanupSwapChain(self, self.swap_chain);

        vkd.destroySampler(self.device, self.texture_sampler, null);
        vkd.destroyImageView(self.device, self.texture_image_view, null);
        vkd.destroyImage(self.device, self.texture_image, null);
        vkd.freeMemory(self.device, self.texture_image_memory, null);

        for (0..max_frames_in_flight) |i| {
            vkd.destroyBuffer(self.device, self.uniform_buffers[i], null);
            vkd.freeMemory(self.device, self.uniform_buffer_memory[i], null);
        }

        vkd.destroyDescriptorPool(self.device, self.descriptor_pool, null);
        vkd.destroyDescriptorSetLayout(self.device, self.descriptor_set_layout, null);
        vkd.destroyBuffer(self.device, self.index_buffer, null);
        vkd.freeMemory(self.device, self.index_buffer_memory, null);
        vkd.destroyBuffer(self.device, self.vertex_buffer, null);
        vkd.freeMemory(self.device, self.vertex_buffer_memory, null);
        vkd.destroyPipeline(self.device, self.graphics_pipeline, null);
        vkd.destroyPipelineLayout(self.device, self.pipeline_layout, null);
        vkd.destroyRenderPass(self.device, self.render_pass, null);

        for (0..max_frames_in_flight) |i| {
            vkd.destroySemaphore(self.device, self.image_available_semaphores[i], null);
            vkd.destroySemaphore(self.device, self.render_finished_semaphores[i], null);
            vkd.destroyFence(self.device, self.in_flight_fences[i], null);
        }

        allocator.free(self.command_buffers);
        allocator.free(self.image_available_semaphores);
        allocator.free(self.render_finished_semaphores);
        allocator.free(self.in_flight_fences);
        allocator.free(self.uniform_buffers);
        allocator.free(self.uniform_buffer_memory);
        allocator.free(self.uniform_buffers_mapped);
        allocator.free(self.descriptor_sets);

        vkd.destroyCommandPool(self.device, self.command_pool, null);
        vkd.destroyDevice(self.device, null);

        if (enable_validation_layers) {
            destroyDebugUtilsMessengerEXT(
                self.instance,
                self.debug_messenger,
                null,
            );
        }

        vki.destroySurfaceKHR(self.instance, self.surface, null);
        vki.destroyInstance(self.instance, null);
    }

    fn debugCallback(
        message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
        message_type: vk.DebugUtilsMessageTypeFlagsEXT,
        p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
        p_user_data: ?*anyopaque,
    ) callconv(vk.vulkan_call_conv) vk.Bool32 {
        std.debug.print("validation layer: {?s}\n", .{p_callback_data.?.p_message});

        if (message_severity.warning_bit_ext or message_severity.error_bit_ext) {
            // Message is important enough to show
        }

        _ = message_type;
        _ = p_user_data;

        return vk.FALSE;
    }
};

pub fn main() !void {
    var app: HelloTriangleApplication = .{};

    try app.run();
}

// NOTE: Main body function from https://vulkan-tutorial.com/Development_environment
pub fn _main() !void {
    glfw.setErrorCallback(errorCallback);

    if (!glfw.init(.{})) {
        std.log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
        std.process.exit(1);
    }

    defer glfw.terminate();

    const extent = vk.Extent2D{ .width = 800, .height = 600 };

    const window = glfw.Window.create(extent.width, extent.height, "Vulkan window", null, null, .{
        .client_api = .no_api,
    }) orelse {
        std.log.err("failed to create GLFW window: {?s}", .{glfw.getErrorString()});
        std.process.exit(1);
    };

    const base_dispatch = try BaseDispatch.load(@as(
        vk.PfnGetInstanceProcAddr,
        @ptrCast(&glfw.getInstanceProcAddress),
    ));

    var extension_count: u32 = undefined;
    _ = try base_dispatch.enumerateInstanceExtensionProperties(null, &extension_count, null);

    const matrix: Mat4x4 = undefined;
    const vec = Vec4.splat(0);

    _ = matrix.mulVec(&vec);

    defer window.destroy();

    while (!window.shouldClose()) {
        glfw.pollEvents();
    }
}
