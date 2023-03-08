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

#if defined(CONFIG_PROC_FS)

#include "nv_compiler.h"
#include "nv-reg.h"
#include "patches.h"
#include "rmil.h"

static const char *__README_warning = \
    "The NVIDIA graphics driver tries to detect potential problems\n"
    "with the host system and warns about them using the system's\n"
    "logging mechanisms. Important warning message are also logged\n"
    "to dedicated text files in this directory.\n";

static const char *__README_patches = \
    "The NVIDIA graphics driver's kernel interface files can be\n"
    "patched to improve compatibility with new Linux kernels or to\n"
    "fix bugs in these files. When applied, each official patch\n"
    "provides a short text file with a short description of itself\n"
    "in this directory.\n";

static struct proc_dir_entry *proc_nvidia;
static struct proc_dir_entry *proc_nvidia_warnings;
static struct proc_dir_entry *proc_nvidia_patches;

extern nv_linux_state_t *nv_linux_devices;

extern char *NVreg_RegistryDwords;
extern char *NVreg_RmMsg;

static char nv_registry_keys[NV_MAX_REGISTRY_KEYS_LENGTH];

#if defined(NV_PROC_DIR_ENTRY_HAS_OWNER)
#define NV_SET_PROC_ENTRY_OWNER(entry) ((entry)->owner = THIS_MODULE)
#else
#define NV_SET_PROC_ENTRY_OWNER(entry)
#endif

#if defined(NV_PROC_CREATE_DATA_PRESENT)
# define NV_CREATE_PROC_ENTRY(name,mode,parent,fops,__data) \
    proc_create_data(name, __mode, parent, fops, __data)
#else
# define NV_CREATE_PROC_ENTRY(name,mode,parent,fops,__data) \
   ({                                                       \
        struct proc_dir_entry *__entry;                     \
        __entry = create_proc_entry(name, mode, parent);    \
        if (__entry != NULL)                                \
        {                                                   \
            NV_SET_PROC_ENTRY_OWNER(__entry);               \
            __entry->proc_fops = fops;                      \
            __entry->data = (__data);                       \
        }                                                   \
        __entry;                                            \
    })
#endif

#if defined(NV_HAVE_PROC_OPS)
#define NV_CREATE_PROC_FILE(filename,parent,__name,__data)               \
   ({                                                                    \
        struct proc_dir_entry *__entry;                                  \
        int __mode = (S_IFREG | S_IRUGO);                                \
        const struct proc_ops *fops = &nv_procfs_##__name##_fops;        \
        if (fops->proc_write != 0)                                       \
            __mode |= S_IWUSR;                                           \
        __entry = proc_create_data(filename, __mode, parent, fops,       \
            __data);                                                     \
        __entry;                                                         \
    })
#else
#define NV_CREATE_PROC_FILE(filename,parent,__name,__data)               \
   ({                                                                    \
        struct proc_dir_entry *__entry;                                  \
        int __mode = (S_IFREG | S_IRUGO);                                \
        const struct file_operations *fops = &nv_procfs_##__name##_fops; \
        if (fops->write != 0)                                            \
            __mode |= S_IWUSR;                                           \
        __entry = NV_CREATE_PROC_ENTRY(filename, __mode, parent, fops,   \
            __data);                                                     \
        __entry;                                                         \
    })
#endif

/*
 * proc_mkdir_mode exists in Linux 2.6.9, but isn't exported until Linux 3.0.
 * Use the older interface instead unless the newer interface is necessary.
 */
#if defined(NV_PROC_REMOVE_PRESENT)
# define NV_PROC_MKDIR_MODE(name, mode, parent)                \
    proc_mkdir_mode(name, mode, parent)
#else
# define NV_PROC_MKDIR_MODE(name, mode, parent)                \
   ({                                                          \
        struct proc_dir_entry *__entry;                        \
        __entry = create_proc_entry(name, mode, parent);       \
        if (__entry != NULL)                                   \
            NV_SET_PROC_ENTRY_OWNER(__entry);                  \
        __entry;                                               \
    })
#endif

#define NV_CREATE_PROC_DIR(name,parent)                        \
   ({                                                          \
        struct proc_dir_entry *__entry;                        \
        int __mode = (S_IFDIR | S_IRUGO | S_IXUGO);            \
        __entry = NV_PROC_MKDIR_MODE(name, __mode, parent);    \
        __entry;                                               \
    })

#if defined(NV_PDE_DATA_PRESENT)
# define NV_PDE_DATA(inode) PDE_DATA(inode)
#else
# define NV_PDE_DATA(inode) PDE(inode)->data
#endif

#if defined(NV_HAVE_PROC_OPS)
#define NV_DEFINE_PROCFS_SINGLE_FILE(__name)                                  \
    static int nv_procfs_open_##__name(                                       \
        struct inode *inode,                                                  \
        struct file *filep                                                    \
    )                                                                         \
    {                                                                         \
        return single_open(filep, nv_procfs_read_##__name,                    \
            NV_PDE_DATA(inode));                                              \
    }                                                                         \
                                                                              \
    static const struct proc_ops nv_procfs_##__name##_fops = {                \
        .proc_open       = nv_procfs_open_##__name,                           \
        .proc_read       = seq_read,                                          \
        .proc_lseek      = seq_lseek,                                         \
        .proc_release    = single_release,                                    \
    };
#else
#define NV_DEFINE_PROCFS_SINGLE_FILE(__name)                                  \
    static int nv_procfs_open_##__name(                                       \
        struct inode *inode,                                                  \
        struct file *filep                                                    \
    )                                                                         \
    {                                                                         \
        return single_open(filep, nv_procfs_read_##__name,                    \
            NV_PDE_DATA(inode));                                              \
    }                                                                         \
                                                                              \
    static const struct file_operations nv_procfs_##__name##_fops = {         \
        .owner      = THIS_MODULE,                                            \
        .open       = nv_procfs_open_##__name,                                \
        .read       = seq_read,                                               \
        .llseek     = seq_lseek,                                              \
        .release    = single_release,                                         \
    };
#endif

static int nv_procfs_read_registry(struct seq_file *s, void *v);

#define NV_PROC_WRITE_BUFFER_SIZE   (64 * RM_PAGE_SIZE)

static int
nv_procfs_read_gpu_info(
    struct seq_file *s,
    void *v
)
{
    nv_state_t *nv = s->private;
    nv_linux_state_t *nvl = NV_GET_NVL_FROM_NV_STATE(nv);
    struct pci_dev *dev = nvl->dev;
    char *type, *fmt, tmpstr[NV_DEVICE_NAME_LENGTH];
    int status;
    NvU8 *uuid;
    NvU32 vbios_rev1, vbios_rev2, vbios_rev3, vbios_rev4, vbios_rev5;
    NvU32 fpga_rev1, fpga_rev2, fpga_rev3;
    nv_stack_t *sp = NULL;

    NV_KMEM_CACHE_ALLOC_STACK(sp);
    if (sp == NULL)
    {
        nv_printf(NV_DBG_ERRORS, "NVRM: failed to allocate stack!\n");
        return 0;
    }

    if (NV_IS_GVI_DEVICE(nv))
    {
        if (rm_gvi_get_device_name(sp, nv, dev->device, NV_DEVICE_NAME_LENGTH,
                                   tmpstr) != RM_OK)
        {
            strcpy (tmpstr, "Unknown");
        }
    }
    else
    {
        if (rm_get_device_name(sp, nv, dev->device, dev->subsystem_vendor,
                    dev->subsystem_device, NV_DEVICE_NAME_LENGTH,
                    tmpstr) != RM_OK)
        {
            strcpy (tmpstr, "Unknown");
        }
    }

    seq_printf(s, "Model: \t\t %s\n", tmpstr);
    seq_printf(s, "IRQ:   \t\t %d\n", nv->interrupt_line);

    if (NV_IS_GVI_DEVICE(nv))
    {
        status = rm_gvi_get_firmware_version(sp, nv, &fpga_rev1, &fpga_rev2,
                                             &fpga_rev3);
        if (status != RM_OK)
            seq_printf(s, "Firmware: \t ????.??.??\n");
        else
        {
            fmt = "Firmware: \t %x.%x.%x\n";
            seq_printf(s, fmt, fpga_rev1, fpga_rev2, fpga_rev3);
        }
    }
    else
    {
        if (rm_get_gpu_uuid(sp, nv, &uuid, NULL) == RM_OK)
        {
            seq_printf(s, "GPU UUID: \t %s\n", (char *)uuid);
            os_free_mem(uuid);
        }

        if (rm_get_vbios_version(sp, nv, &vbios_rev1, &vbios_rev2,
                    &vbios_rev3, &vbios_rev4,
                    &vbios_rev5) != RM_OK)
        {
            seq_printf(s, "Video BIOS: \t ??.??.??.??.??\n");
        }
        else
        {
            fmt = "Video BIOS: \t %02x.%02x.%02x.%02x.%02x\n";
            seq_printf(s, fmt, vbios_rev1, vbios_rev2, vbios_rev3, vbios_rev4,
                       vbios_rev5);
        }
    }

    if (nv_find_pci_capability(dev, PCI_CAP_ID_AGP))
        type = "AGP";
    else if (nv_find_pci_capability(dev, PCI_CAP_ID_EXP))
        type = "PCIe";
    else
        type = "PCI";
    seq_printf(s, "Bus Type: \t %s\n", type);

    seq_printf(s, "DMA Size: \t %d bits\n",
     nv_count_bits(dev->dma_mask));
    seq_printf(s, "DMA Mask: \t 0x%llx\n", dev->dma_mask);
    seq_printf(s, "Bus Location: \t %04x:%02x.%02x.%x\n",
               nv->domain, nv->bus, nv->slot, PCI_FUNC(dev->devfn));
#if defined(DEBUG)
    do
    {
        int j;
        for (j = 0; j < NV_GPU_NUM_BARS; j++)
        {
            seq_printf(s, "BAR%u: \t\t 0x%llx (%lluMB)\n",
                       j, nv->bars[j].address, (nv->bars[j].size >> 20));
        }
    } while (0);
#endif

    NV_KMEM_CACHE_FREE_STACK(sp);

    return 0;
}

NV_DEFINE_PROCFS_SINGLE_FILE(gpu_info);

static int
nv_procfs_read_version(
    struct seq_file *s,
    void *v
)
{
    seq_printf(s, "NVRM version: %s\n", pNVRM_ID);
    seq_printf(s, "GCC version:  %s\n", NV_COMPILER);

    return 0;
}

NV_DEFINE_PROCFS_SINGLE_FILE(version);

static struct pci_dev *nv_get_agp_device_by_class(unsigned int class)
{
    struct pci_dev *dev, *fdev;
    u32 slot, func;

    dev = NV_PCI_GET_CLASS(class << 8, NULL);
    while (dev)
    {
        slot = NV_PCI_SLOT_NUMBER(dev);
        for (func = 0; func < 8; func++)
        {
            fdev = NV_GET_DOMAIN_BUS_AND_SLOT(NV_PCI_DOMAIN_NUMBER(dev),
                                              NV_PCI_BUS_NUMBER(dev),
                                              PCI_DEVFN(slot, func));
            if (!fdev)
                continue;
            if (nv_find_pci_capability(fdev, PCI_CAP_ID_AGP))
            {
                NV_PCI_DEV_PUT(dev);
                return fdev;
            }
            NV_PCI_DEV_PUT(fdev);
        }
        dev = NV_PCI_GET_CLASS(class << 8, dev);
    }

    return NULL;
}

static int
nv_procfs_read_agp_info(
    struct seq_file *s,
    void *v
)
{
    nv_state_t *nv = s->private;
    nv_linux_state_t *nvl = NULL;
    struct pci_dev *dev;
    char   *fw, *sba;
    u8     cap_ptr;
    u32    status, command, agp_rate;

    if (nv != NULL)
    {
        nvl = NV_GET_NVL_FROM_NV_STATE(nv);
        dev = nvl->dev;
    }
    else
    {
        dev = nv_get_agp_device_by_class(PCI_CLASS_BRIDGE_HOST);
        if (!dev)
            return 0;

        seq_printf(s, "Host Bridge: \t ");

#if defined(CONFIG_PCI_NAMES)
        seq_printf(s, "%s\n", NV_PCI_DEVICE_NAME(dev));
#else
        seq_printf(s, "PCI device %04x:%04x\n", dev->vendor, dev->device);
#endif
    }

    cap_ptr = nv_find_pci_capability(dev, PCI_CAP_ID_AGP);

    pci_read_config_dword(dev, cap_ptr + 4, &status);
    pci_read_config_dword(dev, cap_ptr + 8, &command);

    fw  = (status & 0x00000010) ? "Supported" : "Not Supported";
    sba = (status & 0x00000200) ? "Supported" : "Not Supported";

    seq_printf(s, "Fast Writes: \t %s\n", fw);
    seq_printf(s, "SBA: \t\t %s\n", sba);

    agp_rate = status & 0x7;
    if (status & 0x8)
        agp_rate <<= 2;

    seq_printf(s, "AGP Rates: \t %s%s%s%s\n",
               (agp_rate & 0x00000008) ? "8x " : "",
               (agp_rate & 0x00000004) ? "4x " : "",
               (agp_rate & 0x00000002) ? "2x " : "",
               (agp_rate & 0x00000001) ? "1x " : "");

    seq_printf(s, "Registers: \t 0x%08x:0x%08x\n", status, command);

    if (nvl == NULL)
        NV_PCI_DEV_PUT(dev);

    return 0;
}

NV_DEFINE_PROCFS_SINGLE_FILE(agp_info);

static int
nv_procfs_read_agp_status(
    struct seq_file *s,
    void *v
)
{
    nv_state_t *nv = s->private;
    struct pci_dev *dev;
    char   *fw, *sba, *drv;
    u8     cap_ptr;
    u32    scratch;
    u32    status, command, agp_rate;
    nv_stack_t *sp = NULL;

    dev = nv_get_agp_device_by_class(PCI_CLASS_BRIDGE_HOST);
    if (!dev)
        return 0;
    cap_ptr = nv_find_pci_capability(dev, PCI_CAP_ID_AGP);

    pci_read_config_dword(dev, cap_ptr + 4, &status);
    pci_read_config_dword(dev, cap_ptr + 8, &command);
    NV_PCI_DEV_PUT(dev);

    dev = nv_get_agp_device_by_class(PCI_CLASS_DISPLAY_VGA);
    if (!dev)
        return 0;
    cap_ptr = nv_find_pci_capability(dev, PCI_CAP_ID_AGP);

    pci_read_config_dword(dev, cap_ptr + 4, &scratch);
    status &= scratch;
    pci_read_config_dword(dev, cap_ptr + 8, &scratch);
    command &= scratch;

    if (NV_AGP_ENABLED(nv) && (command & 0x100))
    {
        seq_printf(s, "Status: \t Enabled\n");

        drv = NV_OSAGP_ENABLED(nv) ? "AGPGART" : "NVIDIA";
        seq_printf(s, "Driver: \t %s\n", drv);

        agp_rate = command & 0x7;
        if (status & 0x8)
            agp_rate <<= 2;

        seq_printf(s, "AGP Rate: \t %dx\n", agp_rate);

        fw = (command & 0x00000010) ? "Enabled" : "Disabled";
        seq_printf(s, "Fast Writes: \t %s\n", fw);

        sba = (command & 0x00000200) ? "Enabled" : "Disabled";
        seq_printf(s, "SBA: \t\t %s\n", sba);
    }
    else
    {
        int agp_config = 0;

        NV_KMEM_CACHE_ALLOC_STACK(sp);
        if (sp == NULL)
        {
            nv_printf(NV_DBG_ERRORS, "NVRM: failed to allocate stack!\n");
            return 0;
        }

        seq_printf(s, "Status: \t Disabled\n\n");

        /*
         * If we find AGP is disabled, but the RM registry indicates it
         * was requested, direct the user to the kernel log (we, or even
         * the kernel may have printed a warning/an error message).
         *
         * Note that the "XNvAGP" registry key reflects the user request
         * and overrides the RM "NvAGP" key, if present.
         */
        rm_read_registry_dword(sp, nv, "NVreg", "NvAGP",  &agp_config);
        rm_read_registry_dword(sp, nv, "NVreg", "XNvAGP", &agp_config);

        if (agp_config != NVOS_AGP_CONFIG_DISABLE_AGP && NV_AGP_FAILED(nv))
        {
            seq_printf(s,
                  "AGP initialization failed, please check the ouput  \n"
                  "of the 'dmesg' command and/or your system log file \n"
                  "for additional information on this problem.        \n");
        }

        NV_KMEM_CACHE_FREE_STACK(sp);
    }

    NV_PCI_DEV_PUT(dev);
    return 0;
}

NV_DEFINE_PROCFS_SINGLE_FILE(agp_status);

static int
nv_procfs_open_registry(
    struct inode *inode,
    struct file  *file
)
{
    nv_file_private_t *nvfp = NULL;
    nv_stack_t *sp = NULL;

    nvfp = nv_alloc_file_private();
    if (nvfp == NULL)
    {
        nv_printf(NV_DBG_ERRORS, "NVRM: failed to allocate file private!\n");
        return -ENOMEM;
    }

    nvfp->proc_data = NV_PDE_DATA(inode);

    if (0 == (file->f_mode & FMODE_WRITE))
        goto done;

    NV_KMEM_CACHE_ALLOC_STACK(sp);
    if (sp == NULL)
    {
        nv_free_file_private(nvfp);
        nv_printf(NV_DBG_ERRORS, "NVRM: failed to allocate stack!\n");
        return -ENOMEM;
    }

    if (RM_OK != os_alloc_mem((void **)&nvfp->data, NV_PROC_WRITE_BUFFER_SIZE))
    {
        nv_free_file_private(nvfp);
        NV_KMEM_CACHE_FREE_STACK(sp);
        return -ENOMEM;
    }

    os_mem_set((void *)nvfp->data, 0, NV_PROC_WRITE_BUFFER_SIZE);
    nvfp->fops_sp[NV_FOPS_STACK_INDEX_PROCFS] = sp;

done:
    single_open(file, nv_procfs_read_registry, nvfp);

    return 0;
}

static int
nv_procfs_close_registry(
    struct inode *inode,
    struct file  *file
)
{
    struct seq_file *s = file->private_data;
    nv_file_private_t *nvfp;
    nv_state_t *nv;
    nv_linux_state_t *nvl = NULL;
    nv_stack_t *sp = NULL;
    char *key_name, *key_value, *registry_keys;
    size_t key_len, len;
    long count;
    RM_STATUS rm_status;
    int rc = 0;

    nvfp = s->private;
    single_release(inode, file);

    sp = nvfp->fops_sp[NV_FOPS_STACK_INDEX_PROCFS];

    if (0 != nvfp->off)
    {
        nv = nvfp->proc_data;
        if (nv != NULL)
            nvl = NV_GET_NVL_FROM_NV_STATE(nv);
        key_value = (char *)nvfp->data;

        key_name = strsep(&key_value, "=");

        if (NULL == key_name || NULL == key_value)
        {
            rc = -EINVAL;
            goto done;
        }

        key_len = (strlen(key_name) + 1);
        count = (nvfp->off - key_len);

        if (count <= 0)
        {
            rc = -EINVAL;
            goto done;
        }

        rm_status = rm_write_registry_binary(sp, nv, "NVreg", key_name,
                key_value, count);
        if (rm_status != RM_OK)
        {
            rc = -EFAULT;
            goto done;
        }

        registry_keys = ((nvl != NULL) ?
                nvl->registry_keys : nv_registry_keys);
        if (strstr(registry_keys, key_name) != NULL)
            goto done;
        len = strlen(registry_keys);

        if ((len + key_len + 2) <= NV_MAX_REGISTRY_KEYS_LENGTH)
        {
            if (len != 0)
                strcat(registry_keys, ", ");
            strcat(registry_keys, key_name);
        }
    }

done:
    if (NULL != nvfp->data)
        os_free_mem(nvfp->data);

    nv_free_file_private(nvfp);

    if (sp != NULL)
        NV_KMEM_CACHE_FREE_STACK(sp);

    return rc;
}

static int
nv_procfs_read_params(
    struct seq_file *s,
    void *v
)
{
    unsigned int i;
    nv_parm_t *entry;

    for (i = 0; (entry = &nv_parms[i])->name != NULL; i++)
        seq_printf(s, "%s: %u\n", entry->name, *entry->data);

    seq_printf(s, "RegistryDwords: \"%s\"\n",
                (NVreg_RegistryDwords != NULL) ? NVreg_RegistryDwords : "");
    seq_printf(s, "RmMsg: \"%s\"\n", (NVreg_RmMsg != NULL) ? NVreg_RmMsg : "");

    return 0;
}

NV_DEFINE_PROCFS_SINGLE_FILE(params);

static int
nv_procfs_read_registry(
    struct seq_file *s,
    void *v
)
{
    nv_file_private_t *nvfp = s->private;
    nv_state_t *nv = nvfp->proc_data;
    nv_linux_state_t *nvl = NULL;
    char *registry_keys;

    if (nv != NULL)
        nvl = NV_GET_NVL_FROM_NV_STATE(nv);
    registry_keys = ((nvl != NULL) ?
            nvl->registry_keys : nv_registry_keys);

    seq_printf(s, "Binary: \"%s\"\n", registry_keys);
    return 0;
}

static ssize_t
nv_procfs_write_registry(
    struct file   *file,
    const char *buffer,
    size_t count,
    loff_t *pos
)
{
    int status = 0;
    struct seq_file *s = file->private_data;
    nv_file_private_t *nvfp = s->private;
    char *proc_buffer;
    unsigned long bytes_left;

    down(&nvfp->fops_sp_lock[NV_FOPS_STACK_INDEX_PROCFS]);

    bytes_left = (NV_PROC_WRITE_BUFFER_SIZE - nvfp->off - 1);

    if (count == 0)
    {
        status = -EINVAL;
        goto done;
    }
    else if ((bytes_left == 0) || (count > bytes_left))
    {
        status = -ENOSPC;
        goto done;
    }

    proc_buffer = &((char *)nvfp->data)[nvfp->off];

    if (copy_from_user(proc_buffer, buffer, count))
    {
        nv_printf(NV_DBG_ERRORS, "NVRM: failed to copy in proc data!\n");
        status = -EFAULT;
    }
    else
    {
        nvfp->off += count;
    }

    *pos = nvfp->off;

done:
    up(&nvfp->fops_sp_lock[NV_FOPS_STACK_INDEX_PROCFS]);

    return ((status < 0) ? status : (int)count);
}

#if defined(NV_HAVE_PROC_OPS)
static struct proc_ops nv_procfs_registry_fops = {
    .proc_open    = nv_procfs_open_registry,
    .proc_read    = seq_read,
    .proc_write   = nv_procfs_write_registry,
    .proc_lseek   = seq_lseek,
    .proc_release = nv_procfs_close_registry,
};
#else
static struct file_operations nv_procfs_registry_fops = {
    .owner   = THIS_MODULE,
    .open    = nv_procfs_open_registry,
    .read    = seq_read,
    .write   = nv_procfs_write_registry,
    .llseek  = seq_lseek,
    .release = nv_procfs_close_registry,
};
#endif

static int
nv_procfs_read_text_file(
    struct seq_file *s,
    void *v
)
{
    seq_puts(s, s->private);
    return 0;
}

NV_DEFINE_PROCFS_SINGLE_FILE(text_file);

static void
nv_procfs_add_text_file(
    struct proc_dir_entry *parent,
    const char *filename,
    const char *text
)
{
    NV_CREATE_PROC_FILE(filename, parent, text_file, (void *)text);
}

static void nv_procfs_unregister_all(struct proc_dir_entry *entry)
{
#if defined(NV_PROC_REMOVE_PRESENT)
    proc_remove(entry);
#else
    while (entry)
    {
        struct proc_dir_entry *next = entry->next;
        if (entry->subdir)
            nv_procfs_unregister_all(entry->subdir);
        remove_proc_entry(entry->name, entry->parent);
        if (entry == proc_nvidia)
            break;
        entry = next;
    }
#endif
}
#endif

void nv_procfs_add_warning(
    const char *filename,
    const char *text
)
{
#if defined(CONFIG_PROC_FS)
    nv_procfs_add_text_file(proc_nvidia_warnings, filename, text);
#endif
}

int nv_register_procfs(void)
{
#if defined(CONFIG_PROC_FS)
    nv_state_t *nv;
    nv_linux_state_t *nvl;
    NvU32 i = 0;
    char name[6];

    struct proc_dir_entry *entry;
    struct proc_dir_entry *proc_nvidia_agp;
    struct proc_dir_entry *proc_nvidia_gpus, *proc_nvidia_gpu;

    proc_nvidia = NV_CREATE_PROC_DIR("driver/nvidia", NULL);
    if (!proc_nvidia)
        goto failed;

    entry = NV_CREATE_PROC_FILE("params", proc_nvidia, params, NULL);
    if (!entry)
        goto failed;

    entry = NV_CREATE_PROC_FILE("registry", proc_nvidia, registry, NULL);
    if (!entry)
        goto failed;

    proc_nvidia_warnings = NV_CREATE_PROC_DIR("warnings", proc_nvidia);
    if (!proc_nvidia_warnings)
        goto failed;
    nv_procfs_add_text_file(proc_nvidia_warnings, "README", __README_warning);

    proc_nvidia_patches = NV_CREATE_PROC_DIR("patches", proc_nvidia);
    if (!proc_nvidia_patches)
        goto failed;

    for (i = 0; __nv_patches[i].short_description; i++)
    {
        nv_procfs_add_text_file(proc_nvidia_patches,
            __nv_patches[i].short_description, __nv_patches[i].description);
    }

    nv_procfs_add_text_file(proc_nvidia_patches, "README", __README_patches);

    entry = NV_CREATE_PROC_FILE("version", proc_nvidia, version, NULL);
    if (!entry)
        goto failed;

    proc_nvidia_gpus = NV_CREATE_PROC_DIR("gpus", proc_nvidia);
    if (!proc_nvidia_gpus)
        goto failed;

    for (nvl = nv_linux_devices; nvl != NULL;  nvl = nvl->next)
    {
        nv = NV_STATE_PTR(nvl);

        snprintf(name, sizeof(name), "%u", i++);
        proc_nvidia_gpu = NV_CREATE_PROC_DIR(name, proc_nvidia_gpus);
        if (!proc_nvidia_gpu)
            goto failed;

        entry = NV_CREATE_PROC_FILE("information", proc_nvidia_gpu, gpu_info,
            nv);
        if (!entry)
            goto failed;

        entry = NV_CREATE_PROC_FILE("registry", proc_nvidia_gpu, registry, nv);
        if (!entry)
            goto failed;

        if (nv_find_pci_capability(nvl->dev, PCI_CAP_ID_AGP))
        {
            proc_nvidia_agp = NV_CREATE_PROC_DIR("agp", proc_nvidia);
            if (!proc_nvidia_agp)
                goto failed;

            entry = NV_CREATE_PROC_FILE("status", proc_nvidia_agp, agp_status,
                nv);
            if (!entry)
                goto failed;

            entry = NV_CREATE_PROC_FILE("host-bridge", proc_nvidia_agp,
                agp_info, NULL);
            if (!entry)
                goto failed;

            entry = NV_CREATE_PROC_FILE("gpu", proc_nvidia_agp, agp_info, nv);
            if (!entry)
                goto failed;
        }
    }
#endif
    return 0;
#if defined(CONFIG_PROC_FS)
failed:
    nv_procfs_unregister_all(proc_nvidia);
    return -1;
#endif
}

void nv_unregister_procfs(void)
{
#if defined(CONFIG_PROC_FS)
    nv_procfs_unregister_all(proc_nvidia);
#endif
}
