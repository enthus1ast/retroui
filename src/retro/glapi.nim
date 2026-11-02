## The part of OpenGL ES 2.0 (and of desktop OpenGL 2.1, which has the same
## calls) the GPU renderer uses, loaded at run time: nothing to link, no
## headers, and a program that runs where there is no OpenGL at all. The
## driver hands out the functions (`gpuProc`); `loadGl` fills the table.

type
  GLenum* = uint32
  GLuint* = uint32
  GLint* = int32
  GLsizei* = int32
  GLf32* = float32
  GLboolean* = uint8
  GLbitfield* = uint32

const
  GL_COLOR_BUFFER_BIT* = 0x4000'u32
  GL_TRIANGLES* = 0x0004'u32
  GL_BLEND* = 0x0BE2'u32
  GL_SCISSOR_TEST* = 0x0C11'u32
  GL_DEPTH_TEST* = 0x0B71'u32
  GL_CULL_FACE* = 0x0B44'u32
  GL_DITHER* = 0x0BD0'u32
  GL_SRC_ALPHA* = 0x0302'u32
  GL_ONE_MINUS_SRC_ALPHA* = 0x0303'u32
  GL_ONE* = 1'u32
  GL_ZERO* = 0'u32
  GL_TEXTURE_2D* = 0x0DE1'u32
  GL_TEXTURE0* = 0x84C0'u32
  GL_TEXTURE_MIN_FILTER* = 0x2801'u32
  GL_TEXTURE_MAG_FILTER* = 0x2800'u32
  GL_TEXTURE_WRAP_S* = 0x2802'u32
  GL_TEXTURE_WRAP_T* = 0x2803'u32
  GL_NEAREST* = 0x2600'i32
  GL_LINEAR* = 0x2601'i32
  GL_CLAMP_TO_EDGE* = 0x812F'i32
  GL_RGBA* = 0x1908'u32
  GL_ALPHA* = 0x1906'u32
  GL_UNSIGNED_BYTE* = 0x1401'u32
  GL_FLOAT* = 0x1406'u32
  GL_UNPACK_ALIGNMENT* = 0x0CF5'u32
  GL_PACK_ALIGNMENT* = 0x0D05'u32
  GL_ARRAY_BUFFER* = 0x8892'u32
  GL_STREAM_DRAW* = 0x88E0'u32
  GL_VERTEX_SHADER* = 0x8B31'u32
  GL_FRAGMENT_SHADER* = 0x8B30'u32
  GL_COMPILE_STATUS* = 0x8B81'u32
  GL_LINK_STATUS* = 0x8B82'u32
  GL_INFO_LOG_LENGTH* = 0x8B84'u32
  GL_MAX_TEXTURE_SIZE* = 0x0D33'u32
  GL_VENDOR* = 0x1F00'u32
  GL_RENDERER* = 0x1F01'u32
  GL_VERSION* = 0x1F02'u32
  GL_NO_ERROR* = 0'u32
  GL_OUT_OF_MEMORY* = 0x0505'u32
  GL_FRAMEBUFFER* = 0x8D40'u32
  GL_COLOR_ATTACHMENT0* = 0x8CE0'u32
  GL_FRAMEBUFFER_COMPLETE* = 0x8CD5'u32
  GL_FRAMEBUFFER_BINDING* = 0x8CA6'u32
  GL_VIEWPORT* = 0x0BA2'u32
  GL_CURRENT_PROGRAM* = 0x8B8D'u32
  GL_TEXTURE_BINDING_2D* = 0x8069'u32
  GL_ACTIVE_TEXTURE* = 0x84E0'u32
  GL_ARRAY_BUFFER_BINDING* = 0x8894'u32
  GL_MAX_TEXTURE_IMAGE_UNITS* = 0x8872'u32

type
  GlTable* = object
    ## The functions, once loaded (`ok`).
    ok*: bool
    es*: bool                ## OpenGL ES (else desktop OpenGL)
    getString*: proc (name: GLenum): cstring {.cdecl, gcsafe.}
    getIntegerv*: proc (name: GLenum; v: ptr GLint) {.cdecl, gcsafe.}
    getError*: proc (): GLenum {.cdecl, gcsafe.}
    viewport*: proc (x, y: GLint; w, h: GLsizei) {.cdecl, gcsafe.}
    clearColor*: proc (r, g, b, a: GLf32) {.cdecl, gcsafe.}
    clear*: proc (mask: GLbitfield) {.cdecl, gcsafe.}
    enable*: proc (cap: GLenum) {.cdecl, gcsafe.}
    disable*: proc (cap: GLenum) {.cdecl, gcsafe.}
    blendFunc*: proc (s, d: GLenum) {.cdecl, gcsafe.}
    colorMask*: proc (r, g, b, a: GLboolean) {.cdecl, gcsafe.}
    scissor*: proc (x, y: GLint; w, h: GLsizei) {.cdecl, gcsafe.}
    genTextures*: proc (n: GLsizei; t: ptr GLuint) {.cdecl, gcsafe.}
    deleteTextures*: proc (n: GLsizei; t: ptr GLuint) {.cdecl, gcsafe.}
    bindTexture*: proc (target: GLenum; t: GLuint) {.cdecl, gcsafe.}
    activeTexture*: proc (unit: GLenum) {.cdecl, gcsafe.}
    texImage2D*: proc (target: GLenum; level, internal: GLint; w, h: GLsizei; border: GLint;
                       format, typ: GLenum; data: pointer) {.cdecl, gcsafe.}
    texSubImage2D*: proc (target: GLenum; level, x, y: GLint; w, h: GLsizei;
                          format, typ: GLenum; data: pointer) {.cdecl, gcsafe.}
    texParameteri*: proc (target, name: GLenum; v: GLint) {.cdecl, gcsafe.}
    pixelStorei*: proc (name: GLenum; v: GLint) {.cdecl, gcsafe.}
    readPixels*: proc (x, y: GLint; w, h: GLsizei; format, typ: GLenum; data: pointer) {.cdecl, gcsafe.}
    createShader*: proc (kind: GLenum): GLuint {.cdecl, gcsafe.}
    shaderSource*: proc (s: GLuint; n: GLsizei; src: ptr cstring; lens: ptr GLint) {.cdecl, gcsafe.}
    compileShader*: proc (s: GLuint) {.cdecl, gcsafe.}
    getShaderiv*: proc (s: GLuint; name: GLenum; v: ptr GLint) {.cdecl, gcsafe.}
    getShaderInfoLog*: proc (s: GLuint; n: GLsizei; len: ptr GLsizei; log: cstring) {.cdecl, gcsafe.}
    deleteShader*: proc (s: GLuint) {.cdecl, gcsafe.}
    createProgram*: proc (): GLuint {.cdecl, gcsafe.}
    attachShader*: proc (p, s: GLuint) {.cdecl, gcsafe.}
    bindAttribLocation*: proc (p, i: GLuint; name: cstring) {.cdecl, gcsafe.}
    linkProgram*: proc (p: GLuint) {.cdecl, gcsafe.}
    getProgramiv*: proc (p: GLuint; name: GLenum; v: ptr GLint) {.cdecl, gcsafe.}
    getProgramInfoLog*: proc (p: GLuint; n: GLsizei; len: ptr GLsizei; log: cstring) {.cdecl, gcsafe.}
    useProgram*: proc (p: GLuint) {.cdecl, gcsafe.}
    deleteProgram*: proc (p: GLuint) {.cdecl, gcsafe.}
    getUniformLocation*: proc (p: GLuint; name: cstring): GLint {.cdecl, gcsafe.}
    uniform1i*: proc (loc: GLint; v: GLint) {.cdecl, gcsafe.}
    uniform2f*: proc (loc: GLint; a, b: GLf32) {.cdecl, gcsafe.}
    genBuffers*: proc (n: GLsizei; b: ptr GLuint) {.cdecl, gcsafe.}
    deleteBuffers*: proc (n: GLsizei; b: ptr GLuint) {.cdecl, gcsafe.}
    bindBuffer*: proc (target: GLenum; b: GLuint) {.cdecl, gcsafe.}
    bufferData*: proc (target: GLenum; size: int; data: pointer; usage: GLenum) {.cdecl, gcsafe.}
    vertexAttribPointer*: proc (i: GLuint; size: GLint; typ: GLenum; normalized: GLboolean;
                                stride: GLsizei; offset: pointer) {.cdecl, gcsafe.}
    enableVertexAttribArray*: proc (i: GLuint) {.cdecl, gcsafe.}
    drawArrays*: proc (mode: GLenum; first: GLint; count: GLsizei) {.cdecl, gcsafe.}
    finish*: proc () {.cdecl, gcsafe.}
    flush*: proc () {.cdecl, gcsafe.}
    # (drawing into a texture: for filters on the GPU; nil where the driver has none)
    genFramebuffers*: proc (n: GLsizei; f: ptr GLuint) {.cdecl, gcsafe.}
    deleteFramebuffers*: proc (n: GLsizei; f: ptr GLuint) {.cdecl, gcsafe.}
    bindFramebuffer*: proc (target: GLenum; f: GLuint) {.cdecl, gcsafe.}
    framebufferTexture2D*: proc (target, attach, textarget: GLenum; tex: GLuint; level: GLint) {.cdecl, gcsafe.}
    checkFramebufferStatus*: proc (target: GLenum): GLenum {.cdecl, gcsafe.}
    uniform1f*: proc (loc: GLint; v: GLf32) {.cdecl, gcsafe.}
    uniform1fv*: proc (loc: GLint; n: GLsizei; v: ptr GLf32) {.cdecl, gcsafe.}
    # (for layers mixed on the GPU, `retro/photogpu`; nil where the driver has none)
    uniform4f*: proc (loc: GLint; a, b, c, d: GLf32) {.cdecl, gcsafe.}
    disableVertexAttribArray*: proc (i: GLuint) {.cdecl, gcsafe.}

proc loadGl*(t: var GlTable; getProc: proc (name: cstring): pointer {.nimcall.}; es: bool): bool =
  ## Every function from `getProc` (the driver's); false when one is missing.
  t.es = es
  var missing = false
  template get(field: untyped; name: string) =
    let p = getProc(cstring(name))
    if p == nil: missing = true
    else: t.field = cast[typeof(t.field)](p)
  get(getString, "glGetString")
  get(getIntegerv, "glGetIntegerv")
  get(getError, "glGetError")
  get(viewport, "glViewport")
  get(clearColor, "glClearColor")
  get(clear, "glClear")
  get(enable, "glEnable")
  get(disable, "glDisable")
  get(blendFunc, "glBlendFunc")
  get(colorMask, "glColorMask")
  get(scissor, "glScissor")
  get(genTextures, "glGenTextures")
  get(deleteTextures, "glDeleteTextures")
  get(bindTexture, "glBindTexture")
  get(activeTexture, "glActiveTexture")
  get(texImage2D, "glTexImage2D")
  get(texSubImage2D, "glTexSubImage2D")
  get(texParameteri, "glTexParameteri")
  get(pixelStorei, "glPixelStorei")
  get(readPixels, "glReadPixels")
  get(createShader, "glCreateShader")
  get(shaderSource, "glShaderSource")
  get(compileShader, "glCompileShader")
  get(getShaderiv, "glGetShaderiv")
  get(getShaderInfoLog, "glGetShaderInfoLog")
  get(deleteShader, "glDeleteShader")
  get(createProgram, "glCreateProgram")
  get(attachShader, "glAttachShader")
  get(bindAttribLocation, "glBindAttribLocation")
  get(linkProgram, "glLinkProgram")
  get(getProgramiv, "glGetProgramiv")
  get(getProgramInfoLog, "glGetProgramInfoLog")
  get(useProgram, "glUseProgram")
  get(deleteProgram, "glDeleteProgram")
  get(getUniformLocation, "glGetUniformLocation")
  get(uniform1i, "glUniform1i")
  get(uniform2f, "glUniform2f")
  get(genBuffers, "glGenBuffers")
  get(deleteBuffers, "glDeleteBuffers")
  get(bindBuffer, "glBindBuffer")
  get(bufferData, "glBufferData")
  get(vertexAttribPointer, "glVertexAttribPointer")
  get(enableVertexAttribArray, "glEnableVertexAttribArray")
  get(drawArrays, "glDrawArrays")
  get(finish, "glFinish")
  get(flush, "glFlush")
  template opt(field: untyped; name: string) =
    let p = getProc(cstring(name))
    if p != nil: t.field = cast[typeof(t.field)](p)
  opt(genFramebuffers, "glGenFramebuffers")
  opt(deleteFramebuffers, "glDeleteFramebuffers")
  opt(bindFramebuffer, "glBindFramebuffer")
  opt(framebufferTexture2D, "glFramebufferTexture2D")
  opt(checkFramebufferStatus, "glCheckFramebufferStatus")
  opt(uniform1f, "glUniform1f")
  opt(uniform1fv, "glUniform1fv")
  opt(uniform4f, "glUniform4f")
  opt(disableVertexAttribArray, "glDisableVertexAttribArray")
  t.ok = not missing
  t.ok
