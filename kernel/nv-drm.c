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

#if defined(NV_DRM_DRMP_H_PRESENT)
#include <drm/drmP.h>
#else
#include <uapi/drm/drm.h>
#include <uapi/drm/drm_mode.h>

#include <drm/drm_agpsupport.h>
#include <drm/drm_crtc.h>
#include <drm/drm_drv.h>
#include <drm/drm_prime.h>
#include <drm/drm_pci.h>
#include <drm/drm_ioctl.h>
#include <drm/drm_sysfs.h>
#include <drm/drm_vblank.h>
#include <drm/drm_device.h>
#endif

#if defined(NV_DRM_DRM_GEM_H_PRESENT)
#include <drm/drm_gem.h>
#endif

#include <linux/version.h>

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
#if defined(DRIVER_LEGACY) || LINUX_VERSION_CODE >= KERNEL_VERSION(5, 0, 0)
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
#if LINUX_VERSION_CODE < KERNEL_VERSION(4, 14, 0)
    ret = drm_pci_init(&nv_drm_driver, pci_driver);
#elif LINUX_VERSION_CODE < KERNEL_VERSION(5, 6, 0)
    ret = drm_legacy_pci_init(&nv_drm_driver, pci_driver);
#else
    struct pci_dev *pdev = NULL;
    const struct pci_device_id *pid;
    int i;

    INIT_LIST_HEAD(&nv_drm_driver.legacy_dev_list);
        for (i = 0; pci_driver->id_table[i].vendor != 0; i++) {
                pid = &pci_driver->id_table[i];

        /* Loop around setting up a DRM device for each PCI device
         * matching our ID and device class.  If we had the internal
         * function that pci_get_subsys and pci_get_class used, we'd
         * be able to just pass pid in instead of doing a two-stage
         * thing.
         */
                pdev = NULL;
                while ((pdev =
                        pci_get_subsys(pid->vendor, pid->device, pid->subvendor,
                                       pid->subdevice, pdev)) != NULL) {
                        if ((pdev->class & pid->class_mask) != pid->class)
                                continue;

                        /* stealth mode requires a manual probe */
                        pci_dev_get(pdev);
                        drm_get_pci_dev(pdev, pid, &nv_drm_driver);
                }
        }
#endif
#endif
    return ret;
}

void nv_drm_exit(
    struct pci_driver *pci_driver
)
{
#if defined(NV_DRM_AVAILABLE)
#if LINUX_VERSION_CODE < KERNEL_VERSION(4, 14, 0)
    drm_pci_exit(&nv_drm_driver, pci_driver);
#elif LINUX_VERSION_CODE < KERNEL_VERSION(5, 6, 0)
    drm_legacy_pci_exit(&nv_drm_driver, pci_driver);
#else
    struct drm_device *dev, *tmp;
    list_for_each_entry_safe(dev, tmp, &nv_drm_driver.legacy_dev_list, legacy_dev_list) {
        list_del(&dev->legacy_dev_list);
        drm_put_dev(dev);
    }
    DRM_INFO("Module unloaded\n");
#endif
#endif
}
