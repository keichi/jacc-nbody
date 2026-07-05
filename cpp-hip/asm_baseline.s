	.amdgcn_target "amdgcn-amd-amdhsa--gfx942"
	.amdhsa_code_object_version 6
	.text
	.protected	_Z15calc_acc_devicePKN4util4type4vec4IfEEPS2_jS4_f ; -- Begin function _Z15calc_acc_devicePKN4util4type4vec4IfEEPS2_jS4_f
	.globl	_Z15calc_acc_devicePKN4util4type4vec4IfEEPS2_jS4_f
	.p2align	8
	.type	_Z15calc_acc_devicePKN4util4type4vec4IfEEPS2_jS4_f,@function
_Z15calc_acc_devicePKN4util4type4vec4IfEEPS2_jS4_f: ; @_Z15calc_acc_devicePKN4util4type4vec4IfEEPS2_jS4_f
; %bb.0:
	s_load_dword s6, s[0:1], 0x34
	s_load_dwordx2 s[4:5], s[0:1], 0x8
	s_load_dword s3, s[0:1], 0x10
	v_mov_b32_e32 v9, 0
	v_mov_b32_e32 v1, v9
	s_waitcnt lgkmcnt(0)
	s_and_b32 s6, s6, 0xffff
	s_mul_i32 s2, s2, s6
	v_add_u32_e32 v8, s2, v0
	s_cmp_eq_u32 s3, 0
	v_mov_b32_e32 v0, v9
	v_mov_b32_e32 v2, v9
	s_cbranch_scc1 .LBB0_3
; %bb.1:                                ; %.lr.ph.preheader
	s_load_dwordx2 s[6:7], s[0:1], 0x0
	s_load_dwordx2 s[8:9], s[0:1], 0x18
	s_load_dword s2, s[0:1], 0x20
	v_mov_b32_e32 v2, 0
	s_waitcnt lgkmcnt(0)
	v_lshl_add_u64 v[0:1], v[8:9], 4, s[6:7]
	global_load_dwordx3 v[4:6], v[0:1], off
	s_add_u32 s0, s8, 8
	s_addc_u32 s1, s9, 0
	s_mov_b32 s6, 0x800000
	v_mov_b32_e32 v0, 0
	v_mov_b32_e32 v1, v2
.LBB0_2:                                ; %.lr.ph
                                        ; =>This Inner Loop Header: Depth=1
	s_add_u32 s8, s0, -8
	s_addc_u32 s9, s1, -1
	s_load_dwordx4 s[8:11], s[8:9], 0x0
	s_add_i32 s3, s3, -1
	s_add_u32 s0, s0, 16
	s_addc_u32 s1, s1, 0
	s_cmp_eq_u32 s3, 0
	s_waitcnt vmcnt(0) lgkmcnt(0)
	v_pk_add_f32 v[10:11], s[8:9], v[4:5] neg_lo:[0,1] neg_hi:[0,1]
	v_sub_f32_e32 v3, s10, v6
	v_pk_mul_f32 v[12:13], v[10:11], v[10:11]
	s_nop 0
	v_add_f32_e32 v7, s2, v12
	v_add_f32_e32 v7, v7, v13
	v_fmac_f32_e32 v7, v3, v3
	v_mul_f32_e32 v12, 0x4b800000, v7
	v_cmp_gt_f32_e32 vcc, s6, v7
	s_nop 1
	v_cndmask_b32_e32 v7, v7, v12, vcc
	v_rsq_f32_e32 v7, v7
	s_nop 0
	v_mul_f32_e32 v12, 0x45800000, v7
	v_cndmask_b32_e32 v7, v7, v12, vcc
	v_mul_f32_e32 v12, v7, v7
	v_mul_f32_e32 v7, v7, v12
	v_mul_f32_e32 v12, s11, v7
	v_pk_fma_f32 v[0:1], v[10:11], v[12:13], v[0:1] op_sel_hi:[1,0,1]
	v_fmac_f32_e32 v2, v3, v12
	s_cbranch_scc0 .LBB0_2
.LBB0_3:                                ; %Flow67
	v_lshl_add_u64 v[4:5], v[8:9], 4, s[4:5]
	v_mov_b32_e32 v3, 0
	global_store_dwordx4 v[4:5], v[0:3], off
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel _Z15calc_acc_devicePKN4util4type4vec4IfEEPS2_jS4_f
		.amdhsa_group_segment_fixed_size 0
		.amdhsa_private_segment_fixed_size 0
		.amdhsa_kernarg_size 296
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_dispatch_ptr 0
		.amdhsa_user_sgpr_queue_ptr 0
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_user_sgpr_dispatch_id 0
		.amdhsa_user_sgpr_kernarg_preload_length 0
		.amdhsa_user_sgpr_kernarg_preload_offset 0
		.amdhsa_user_sgpr_private_segment_size 0
		.amdhsa_uses_dynamic_stack 0
		.amdhsa_enable_private_segment 0
		.amdhsa_system_sgpr_workgroup_id_x 1
		.amdhsa_system_sgpr_workgroup_id_y 0
		.amdhsa_system_sgpr_workgroup_id_z 0
		.amdhsa_system_sgpr_workgroup_info 0
		.amdhsa_system_vgpr_workitem_id 0
		.amdhsa_next_free_vgpr 14
		.amdhsa_next_free_sgpr 12
		.amdhsa_accum_offset 16
		.amdhsa_reserve_vcc 1
		.amdhsa_float_round_mode_32 0
		.amdhsa_float_round_mode_16_64 0
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_float_denorm_mode_16_64 3
		.amdhsa_dx10_clamp 1
		.amdhsa_ieee_mode 1
		.amdhsa_fp16_overflow 0
		.amdhsa_tg_split 0
		.amdhsa_exception_fp_ieee_invalid_op 0
		.amdhsa_exception_fp_denorm_src 0
		.amdhsa_exception_fp_ieee_div_zero 0
		.amdhsa_exception_fp_ieee_overflow 0
		.amdhsa_exception_fp_ieee_underflow 0
		.amdhsa_exception_fp_ieee_inexact 0
		.amdhsa_exception_int_div_zero 0
	.end_amdhsa_kernel
	.text
.Lfunc_end0:
	.size	_Z15calc_acc_devicePKN4util4type4vec4IfEEPS2_jS4_f, .Lfunc_end0-_Z15calc_acc_devicePKN4util4type4vec4IfEEPS2_jS4_f
                                        ; -- End function
	.set _Z15calc_acc_devicePKN4util4type4vec4IfEEPS2_jS4_f.num_vgpr, 14
	.set _Z15calc_acc_devicePKN4util4type4vec4IfEEPS2_jS4_f.num_agpr, 0
	.set _Z15calc_acc_devicePKN4util4type4vec4IfEEPS2_jS4_f.numbered_sgpr, 12
	.set _Z15calc_acc_devicePKN4util4type4vec4IfEEPS2_jS4_f.num_named_barrier, 0
	.set _Z15calc_acc_devicePKN4util4type4vec4IfEEPS2_jS4_f.private_seg_size, 0
	.set _Z15calc_acc_devicePKN4util4type4vec4IfEEPS2_jS4_f.uses_vcc, 1
	.set _Z15calc_acc_devicePKN4util4type4vec4IfEEPS2_jS4_f.uses_flat_scratch, 0
	.set _Z15calc_acc_devicePKN4util4type4vec4IfEEPS2_jS4_f.has_dyn_sized_stack, 0
	.set _Z15calc_acc_devicePKN4util4type4vec4IfEEPS2_jS4_f.has_recursion, 0
	.set _Z15calc_acc_devicePKN4util4type4vec4IfEEPS2_jS4_f.has_indirect_call, 0
	.section	.AMDGPU.csdata,"",@progbits
; Kernel info:
; codeLenInByte = 304
; TotalNumSgprs: 18
; NumVgprs: 14
; NumAgprs: 0
; TotalNumVgprs: 14
; ScratchSize: 0
; MemoryBound: 0
; FloatMode: 240
; IeeeMode: 1
; LDSByteSize: 0 bytes/workgroup (compile time only)
; SGPRBlocks: 2
; VGPRBlocks: 1
; NumSGPRsForWavesPerEU: 18
; NumVGPRsForWavesPerEU: 14
; AccumOffset: 16
; Occupancy: 8
; WaveLimiterHint : 0
; COMPUTE_PGM_RSRC2:SCRATCH_EN: 0
; COMPUTE_PGM_RSRC2:USER_SGPR: 2
; COMPUTE_PGM_RSRC2:TRAP_HANDLER: 0
; COMPUTE_PGM_RSRC2:TGID_X_EN: 1
; COMPUTE_PGM_RSRC2:TGID_Y_EN: 0
; COMPUTE_PGM_RSRC2:TGID_Z_EN: 0
; COMPUTE_PGM_RSRC2:TIDIG_COMP_CNT: 0
; COMPUTE_PGM_RSRC3_GFX90A:ACCUM_OFFSET: 3
; COMPUTE_PGM_RSRC3_GFX90A:TG_SPLIT: 0
	.text
	.p2alignl 6, 3212836864
	.fill 256, 4, 3212836864
	.section	.AMDGPU.gpr_maximums,"",@progbits
	.set amdgpu.max_num_vgpr, 0
	.set amdgpu.max_num_agpr, 0
	.set amdgpu.max_num_sgpr, 0
	.text
	.type	__hip_cuid_5ed51af3826f0ab0,@object ; @__hip_cuid_5ed51af3826f0ab0
	.section	.bss,"aw",@nobits
	.globl	__hip_cuid_5ed51af3826f0ab0
__hip_cuid_5ed51af3826f0ab0:
	.byte	0                               ; 0x0
	.size	__hip_cuid_5ed51af3826f0ab0, 1

	.ident	"AMD clang version 22.0.0git (https://github.com/RadeonOpenCompute/llvm-project roc-7.2.0 26014 7b800a19466229b8479a78de19143dc33c3ab9b5)"
	.section	".note.GNU-stack","",@progbits
	.addrsig
	.addrsig_sym __hip_cuid_5ed51af3826f0ab0
	.amdgpu_metadata
---
amdhsa.kernels:
  - .agpr_count:     0
    .args:
      - .address_space:  global
        .offset:         0
        .size:           8
        .value_kind:     global_buffer
      - .actual_access:  write_only
        .address_space:  global
        .offset:         8
        .size:           8
        .value_kind:     global_buffer
      - .offset:         16
        .size:           4
        .value_kind:     by_value
      - .address_space:  global
        .offset:         24
        .size:           8
        .value_kind:     global_buffer
      - .offset:         32
        .size:           4
        .value_kind:     by_value
      - .offset:         40
        .size:           4
        .value_kind:     hidden_block_count_x
      - .offset:         44
        .size:           4
        .value_kind:     hidden_block_count_y
      - .offset:         48
        .size:           4
        .value_kind:     hidden_block_count_z
      - .offset:         52
        .size:           2
        .value_kind:     hidden_group_size_x
      - .offset:         54
        .size:           2
        .value_kind:     hidden_group_size_y
      - .offset:         56
        .size:           2
        .value_kind:     hidden_group_size_z
      - .offset:         58
        .size:           2
        .value_kind:     hidden_remainder_x
      - .offset:         60
        .size:           2
        .value_kind:     hidden_remainder_y
      - .offset:         62
        .size:           2
        .value_kind:     hidden_remainder_z
      - .offset:         80
        .size:           8
        .value_kind:     hidden_global_offset_x
      - .offset:         88
        .size:           8
        .value_kind:     hidden_global_offset_y
      - .offset:         96
        .size:           8
        .value_kind:     hidden_global_offset_z
      - .offset:         104
        .size:           2
        .value_kind:     hidden_grid_dims
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 296
    .language:       OpenCL C
    .language_version:
      - 2
      - 0
    .max_flat_workgroup_size: 1024
    .name:           _Z15calc_acc_devicePKN4util4type4vec4IfEEPS2_jS4_f
    .private_segment_fixed_size: 0
    .sgpr_count:     18
    .sgpr_spill_count: 0
    .symbol:         _Z15calc_acc_devicePKN4util4type4vec4IfEEPS2_jS4_f.kd
    .uniform_work_group_size: 1
    .uses_dynamic_stack: false
    .vgpr_count:     14
    .vgpr_spill_count: 0
    .wavefront_size: 64
amdhsa.target:   amdgcn-amd-amdhsa--gfx942
amdhsa.version:
  - 1
  - 2
...

	.end_amdgpu_metadata
