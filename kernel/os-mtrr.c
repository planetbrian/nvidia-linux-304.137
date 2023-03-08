/* _NVRM_COPYRIGHT_BEGIN_
 *
 * Copyright 1999-2011 by NVIDIA Corporation.  All rights reserved.  All
 * information contained herein is proprietary and confidential to NVIDIA
 * Corporation.  Any use, reproduction, or disclosure without the written
 * permission of NVIDIA Corporation is prohibited.
 *
 * _NVRM_COPYRIGHT_END_
 */

#define  __NO_VERSION__
#include "nv-misc.h"

#include "os-interface.h"
#include "nv-linux.h"

RM_STATUS NV_API_CALL os_set_mem_range(
    NvU64 start,
    NvU64 size,
    NvU32 mode,
    NvS32 *memory_token
)
{
#if defined(CONFIG_MTRR)
    if (mode != NV_MEMORY_WRITECOMBINED)
        return RM_ERROR;

    *memory_token = nv_mtrr_add(start, size);
    if (*memory_token < 0)
    {
        nv_printf(NV_DBG_ERRORS,
            "NVRM: failed to write-combine %lluM @ 0x%0llx.\n",
            (size >> 20), start);
        return RM_ERROR;
    }

    return RM_OK;
#endif
    return RM_ERR_NOT_SUPPORTED;
}

RM_STATUS NV_API_CALL os_unset_mem_range(
    NvU64 start,
    NvU64 size,
    NvS32 memory_token
)
{
#if defined(CONFIG_MTRR)
    nv_mtrr_del(memory_token, start, size);
    return RM_OK;
#endif
    return RM_ERR_NOT_SUPPORTED;
}
