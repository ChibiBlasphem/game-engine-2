#include "imgui.h"
#include "backends/imgui_impl_glfw.h"
#include "backends/imgui_impl_wgpu.h"
#include "imgui_bridge.h"

// s'assure que le backend voit webgpu/webgpu.h
// (inclus indirectement par imgui_impl_wgpu.h)

void igCreateContext(void) {
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
}
void igDestroyContext(void) { ImGui::DestroyContext(); }
void igStyleDark(void) { ImGui::StyleColorsDark(); }

void igGlfwInit(void* glfw_window, bool install_callbacks) {
    ImGui_ImplGlfw_InitForOther((GLFWwindow*)glfw_window, install_callbacks);
}
void igGlfwShutdown(void) { ImGui_ImplGlfw_Shutdown(); }

void igWgpuInit(const ImGuiWgpuInitC* info) {
    ImGui_ImplWGPU_InitInfo ii{};
    ii.Device = (WGPUDevice)info->device;
    ii.NumFramesInFlight = (int)info->frames_in_flight;
    ii.RenderTargetFormat = (WGPUTextureFormat)info->rt_format;
    ii.DepthStencilFormat = (WGPUTextureFormat)info->depth_format;
    // Le backend récupère la queue via le device si nécessaire.
    ImGui_ImplWGPU_Init(&ii);
}
void igWgpuShutdown(void) { ImGui_ImplWGPU_Shutdown(); }

void igNewFrameGlfw(void) { ImGui_ImplGlfw_NewFrame(); }
void igNewFrameWgpu(void) { ImGui_ImplWGPU_NewFrame(); }
void igNewFrame(void) { ImGui::NewFrame(); }
void igRender(void) { ImGui::Render(); }

void igRenderDrawData(void* pass) {
    ImGui_ImplWGPU_RenderDrawData(ImGui::GetDrawData(), (WGPURenderPassEncoder)pass);
}

void igBegin(const char* title, bool* opened, ImGuiWindowFlagsZ flags) { ImGui::Begin(title, opened, flags); }
void igText(const char* text) { ImGui::TextUnformatted(text); }
void igEnd(void) { ImGui::End(); }

void igCheckbox(const char* label, bool* v) { ImGui::Checkbox(label, v); }