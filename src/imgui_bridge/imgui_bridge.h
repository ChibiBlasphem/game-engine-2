#ifdef __cplusplus
extern "C" {
#endif
#include <stdint.h>
#include <stdbool.h>

typedef struct {
    void* device;            // WGPUDevice
    uint32_t rt_format;      // WGPUTextureFormat (u32)
    uint32_t depth_format;   // WGPUTextureFormat (0 si pas de depth pour l’overlay)
    uint32_t frames_in_flight; // 2 ou 3
} ImGuiWgpuInitC;

void igCreateContext(void);
void igDestroyContext(void);
void igStyleDark(void);

// backends init/shutdown
void igGlfwInit(void* glfw_window, bool install_callbacks);
void igGlfwShutdown(void);

void igWgpuInit(const ImGuiWgpuInitC* info);
void igWgpuShutdown(void);

// per-frame
void igNewFrameGlfw(void);
void igNewFrameWgpu(void);
void igNewFrame(void);
void igRender(void);

// encode draw data in a render pass
void igRenderDrawData(void* render_pass_encoder); // WGPURenderPassEncoder

// helpers
void igBegin(const char* title);
void igText(const char* text);
void igEnd(void);

#ifdef __cplusplus
}
#endif