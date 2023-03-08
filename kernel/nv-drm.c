/* _NVRM_COPYRIGHT_BEGIN_
 *
 * Copyright 2013 by NVIDIA Corporation.  All rights reserved.  All
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

#if defined(NV_DRM_AVAILABLE)

#include <drm/drmP.h>

#if defined(NV_DRM_DRM_GEM_H_PRESENT)
#include <drm/drm_gem.h>
#endif

extern nv_linux_state_t *nv_linux_devices;

static int nv_drm_load(
    struct drm_device *dev,
    unsigned long flags
)
{
    nv_linux_state_t *nvl;

    for (nvl = nv_linux_devices; nvl != NULL; nvl = nvl->next)
    {
        if (nvl->dev == dev->pdev)
        {
            return 0;
        }
    }

    return -ENODEV;
}

/**
 * The return type of unload hook was changed from int
 * to void by the following kernel commit:- 
 *       
 * 2017-01-06  11b3c20bdd15d17382068be569740de1dccb173d
 */
static int __nv_drm_unload(
    struct drm_device *dev
)
{
    nv_linux_state_t *nvl;

    for (nvl = nv_linux_devices; nvl != NULL; nvl = nvl->next)
    {
        if (nvl->dev == dev->pdev)
        {
            return 0;
        }
    }

    return -ENODEV;
}

#if defined(NV_DRM_DRIVER_UNLOAD_HAS_INT_RETURN_TYPE)
static int nv_drm_unload(
    struct drm_device *dev
)
{
    return __nv_drm_unload(dev);
}

#else
static void nv_drm_unload(
    struct drm_device *dev
)
{
    __nv_drm_unload(dev);
}
#endif

static const struct file_operations nv_drm_fops = {
    .owner = THIS_MODULE,
    .open = drm_open,
    .release = drm_release,
    .unlocked_ioctl = drm_ioctl,
    .mmap = drm_gem_mmap,
    .poll = drm_poll,
    .read = drm_read,
    .llseek = noop_llseek,
};

static struct drm_driver nv_drm_driver = {
#if defined(DRIVER_LEGACY)
    .driver_features = DRIVER_LEGACY,
#else
    .driver_features = 0,
#endif
    .load = nv_drm_load,
    .unload = nv_drm_unload,
    .fops = &nv_drm_fops,
#if defined(NV_DRM_PCI_SET_BUSID_PRESENT)
    .set_busid = drm_pci_set_busid,
#endif

    .name = "nvidia-drm",
    .desc = "NVIDIA DRM driver",
    .date = "20150116",
    .major = 0,
    .minor = 0,
    .patchlevel = 0,
};
#endif /* defined(NV_DRM_AVAILABLE) */

int __init nv_drm_init(
    struct pci_driver *pci_driver
)
{
    int ret = 0;
#if defined(NV_DRM_AVAILABLE)
    ret = drm_pci_init(&nv_drm_driver, pci_driver);
#endif
    return ret;
}

void nv_drm_exit(
    struct pci_driver *pci_driver
)
{
#if defined(NV_DRM_AVAILABLE)
    drm_pci_exit(&nv_drm_driver, pci_driver);
#endif
}
