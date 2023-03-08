#!/bin/sh

# make sure we are in the directory containing this script
SCRIPTDIR=`dirname $0`
cd $SCRIPTDIR
PATH="${PATH}:/bin:/sbin"

#
# HOSTCC vs. CC - if a conftest needs to build and execute a test
# binary, like get_uname, then $HOSTCC needs to be used for this
# conftest in order for the host/build system to be able to execute
# it in X-compile environments.
# In all other cases, $CC should be used to minimize the risk of
# false failures due to conflicts with architecture specific header
# files.
#
CC="$1"
HOSTCC="$2"
ARCH=$3
ISYSTEM=`$CC -print-file-name=include 2> /dev/null`
SOURCES=$4
HEADERS=$SOURCES/include
OUTPUT=$5
XEN_PRESENT=1
KERNEL_ARCH="$ARCH"

if [ "$ARCH" = "i386" -o "$ARCH" = "x86_64" ]; then
    if [ -d "$SOURCES/arch/x86" ]; then
        KERNEL_ARCH="x86"
    fi
fi

HEADERS_ARCH="$SOURCES/arch/$KERNEL_ARCH/include"

test_xen() {
    #
    # Determine if the target kernel is a Xen kernel. It used to be
    # sufficient to check for CONFIG_XEN, but the introduction of
    # modular para-virtualization (CONFIG_PARAVIRT, etc.) and
    # Xen guest support, it is no longer possible to determine the
    # target environment at build time. Therefore, if both
    # CONFIG_XEN and CONFIG_PARAVIRT are present, text_xen() treats
    # the kernel as a stand-alone kernel.
    #
    OLD_FILE="linux/autoconf.h"
    NEW_FILE="generated/autoconf.h"

    if [ -f $HEADERS/$NEW_FILE -o -f $OUTPUT/include/$NEW_FILE ]; then
        FILE=$NEW_FILE
    fi
    if [ -f $HEADERS/$OLD_FILE -o -f $OUTPUT/include/$OLD_FILE ]; then
        FILE=$OLD_FILE
    fi

    if [ -n "$FILE" ]; then
        #
        # We are looking at a configured source tree; verify
        # that it's not a Xen kernel.
        #
        echo "#include <$FILE>
        #if defined(CONFIG_XEN) && !defined(CONFIG_PARAVIRT)
        #error CONFIG_XEN defined!
        #endif
        " > conftest$$.c

        $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
        rm -f conftest$$.c

        if [ -f conftest$$.o ]; then
            rm -f conftest$$.o
            XEN_PRESENT=0
        fi
    else
        CONFIG=$HEADERS/../.config
        if [ -f $CONFIG ]; then
            if [ -z "$(grep "^CONFIG_XEN=y" $CONFIG)" ]; then
                XEN_PRESENT="0"
                return
            fi
            if [ -n "$(grep "^CONFIG_PARAVIRT=y" $CONFIG)" ]; then
                XEN_PRESENT="0"
            fi
        fi
    fi
}

test_headers() {
    #
    # Determine which header files (of a set that may or may not be
    # present) are provided by the target kernel.
    #
    FILES="asm/system.h"
    FILES="$FILES drm/drmP.h"
    FILES="$FILES drm/drm_gem.h"
    FILES="$FILES generated/autoconf.h"
    FILES="$FILES generated/compile.h"
    FILES="$FILES generated/utsrelease.h"
    FILES="$FILES linux/efi.h"
    FILES="$FILES linux/kconfig.h"
    FILES="$FILES linux/screen_info.h"
    FILES="$FILES linux/semaphore.h"
    FILES="$FILES linux/printk.h"
    FILES="$FILES linux/ratelimit.h"
    FILES="$FILES linux/prio_tree.h"
    FILES="$FILES linux/log2.h"
    FILES="$FILES linux/of.h"
    FILES="$FILES linux/bug.h"
    FILES="$FILES linux/sched/signal.h"
    FILES="$FILES linux/sched/task.h"
    FILES="$FILES xen/ioemu.h"
    FILES="$FILES linux/fence.h"

    FILES_ARCH="$FILES_ARCH asm/set_memory.h"

    translate_and_find_header_files $HEADERS      $FILES
    translate_and_find_header_files $HEADERS_ARCH $FILES_ARCH
}

build_cflags() {
    BASE_CFLAGS="-O2 -D__KERNEL__ \
-DKBUILD_BASENAME=\"#conftest$$\" -DKBUILD_MODNAME=\"#conftest$$\" \
-nostdinc -isystem $ISYSTEM"

    if [ "$OUTPUT" != "$SOURCES" ]; then
        OUTPUT_CFLAGS="-I$OUTPUT/include2 -I$OUTPUT/include"
        if [ -f "$OUTPUT/include/generated/autoconf.h" ]; then
            AUTOCONF_CFLAGS="-include $OUTPUT/include/generated/autoconf.h"
        else
            AUTOCONF_CFLAGS="-include $OUTPUT/include/linux/autoconf.h"
        fi
    else
        if [ -f "$HEADERS/generated/autoconf.h" ]; then
            AUTOCONF_CFLAGS="-include $HEADERS/generated/autoconf.h"
        else
            AUTOCONF_CFLAGS="-include $HEADERS/linux/autoconf.h"
        fi
    fi

    CFLAGS="$CFLAGS $OUTPUT_CFLAGS -I$HEADERS $AUTOCONF_CFLAGS"

    test_xen

    if [ "$OUTPUT" != "$SOURCES" ]; then
        MACH_CFLAGS="-I$HEADERS/asm-$ARCH/mach-default"
        if [ "$ARCH" = "i386" -o "$ARCH" = "x86_64" ]; then
            MACH_CFLAGS="$MACH_CFLAGS -I$HEADERS/asm-x86/mach-default"
            MACH_CFLAGS="$MACH_CFLAGS -I$SOURCES/arch/x86/include/asm/mach-default"
            MACH_CFLAGS="$MACH_CFLAGS -I$HEADERS/arch/x86/include/uapi"
        elif [ "$ARCH" = "arm" ]; then
            MACH_CFLAGS="$MACH_CFLAGS -D__LINUX_ARM_ARCH__=7"
            MACH_CFLAGS="$MACH_CFLAGS -I$SOURCES/arch/arm/mach-tegra/include"
            MACH_CFLAGS="$MACH_CFLAGS -I$HEADERS/arch/arm/include/uapi"
        fi
        if [ "$XEN_PRESENT" != "0" ]; then
            MACH_CFLAGS="-I$HEADERS/asm-$ARCH/mach-xen $MACH_CFLAGS"
        fi
    else
        MACH_CFLAGS="-I$HEADERS/asm/mach-default"
        if [ "$ARCH" = "i386" -o "$ARCH" = "x86_64" ]; then
            MACH_CFLAGS="$MACH_CFLAGS -I$HEADERS/asm-x86/mach-default"
            MACH_CFLAGS="$MACH_CFLAGS -I$SOURCES/arch/x86/include/asm/mach-default"
            MACH_CFLAGS="$MACH_CFLAGS -I$HEADERS/arch/x86/include/uapi"
        elif [ "$ARCH" = "arm" ]; then
            MACH_CFLAGS="$MACH_CFLAGS -D__LINUX_ARM_ARCH__=7"
            MACH_CFLAGS="$MACH_CFLAGS -I$SOURCES/arch/arm/mach-tegra/include"
            MACH_CFLAGS="$MACH_CFLAGS -I$HEADERS/arch/arm/include/uapi"
        fi
        if [ "$XEN_PRESENT" != "0" ]; then
            MACH_CFLAGS="-I$HEADERS/asm/mach-xen $MACH_CFLAGS"
        fi
    fi

    CFLAGS="$BASE_CFLAGS $MACH_CFLAGS $OUTPUT_CFLAGS $AUTOCONF_CFLAGS"
    CFLAGS="$CFLAGS -I$HEADERS -I$HEADERS/uapi -I$OUTPUT/include/generated/uapi"

    if [ "$ARCH" = "i386" -o "$ARCH" = "x86_64" ]; then
        CFLAGS="$CFLAGS -I$SOURCES/arch/x86/include"
        CFLAGS="$CFLAGS -I$SOURCES/arch/x86/include/uapi"
        CFLAGS="$CFLAGS -I$OUTPUT/arch/x86/include/generated"
        CFLAGS="$CFLAGS -I$OUTPUT/arch/x86/include/generated/uapi"
    elif [ "$ARCH" = "arm" ]; then
        CFLAGS="$CFLAGS -I$SOURCES/arch/arm/include"
        CFLAGS="$CFLAGS -I$SOURCES/arch/arm/include/uapi"
        CFLAGS="$CFLAGS -I$OUTPUT/arch/arm/include/generated"
        CFLAGS="$CFLAGS -I$OUTPUT/arch/arm/include/generated/uapi"
    fi
    if [ -n "$BUILD_PARAMS" ]; then
        CFLAGS="$CFLAGS -D$BUILD_PARAMS"
    fi
}

CONFTEST_PREAMBLE="#include \"conftest.h\"
    #if defined(NV_LINUX_KCONFIG_H_PRESENT)
    #include <linux/kconfig.h>
    #endif
    #if defined(NV_GENERATED_AUTOCONF_H_PRESENT)
    #include <generated/autoconf.h>
    #else
    #include <linux/autoconf.h>
    #endif
    #if defined(CONFIG_XEN) && \
        defined(CONFIG_XEN_INTERFACE_VERSION) &&  !defined(__XEN_INTERFACE_VERSION__)
    #define __XEN_INTERFACE_VERSION__ CONFIG_XEN_INTERFACE_VERSION
    #endif"

append_conftest() {
    #
    # Helper function to make it easier to import conftests from newer
    # driver versions by appending stdin to conftest.h
    #

    while read LINE; do
        echo ${LINE} >> conftest.h
    done
}

translate_and_find_header_files() {
    # Inputs:
    #   $1: a parent directory (full path), in which to search
    #   $2: a list of relative file paths
    #
    # This routine creates an upper case, underscore version of each of the
    # relative file paths, and uses that as the token to either define or
    # undefine in a C header file. For example, linux/fence.h becomes
    # NV_LINUX_FENCE_H_PRESENT, and that is either defined or undefined, in the
    # output (which goes to stdout, just like the rest of this file).

    local parent_dir=$1
    shift

    for file in $@; do
        local file_define=NV_`echo $file | tr '/.' '_' | tr '-' '_' | tr 'a-z' 'A-Z'`_PRESENT
        if [ -f $parent_dir/$file -o -f $OUTPUT/include/$file ]; then
            echo "#define $file_define" | append_conftest "headers"
        else
            echo "#undef $file_define" | append_conftest "headers"
        fi
    done
}

compile_check_conftest() {
    #
    # Compile the current conftest C file and check+output the result
    #
    CODE="$1"
    DEF="$2"
    VAL="$3"
    CAT="$4"

    echo "$CONFTEST_PREAMBLE
    $CODE" > conftest$$.c

    $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
    rm -f conftest$$.c

    if [ -f conftest$$.o ]; then
        rm -f conftest$$.o
        if [ "${CAT}" = "functions" ]; then
            # The logic for "functions" compilation tests is inverted compared to
            # other compilation steps: if the function is present, the code
            # snippet will fail to compile because the function call won't match
            # the prototype. If the function is not present, the code snippet
            # will produce an object file with the function as an unresolved
            # symbol.
            echo "#undef ${DEF}" | append_conftest "${CAT}"
        else
            echo "#define ${DEF} ${VAL}" | append_conftest "${CAT}"
        fi
        return
    else
        if [ "${CAT}" = "functions" ]; then
            echo "#define ${DEF} ${VAL}" | append_conftest "${CAT}"
        else
            echo "#undef ${DEF}" | append_conftest "${CAT}"
        fi
        return
    fi
}

compile_test() {
    case "$1" in
        remap_page_range)
            #
            # Determine if the remap_page_range() function is present
            # and how many arguments it takes.
            #
            echo "$CONFTEST_PREAMBLE
            #include <linux/mm.h>
            void conftest_remap_page_range(void) {
                remap_page_range();
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                echo "#undef NV_REMAP_PAGE_RANGE_PRESENT" >> conftest.h
                rm -f conftest$$.o
                return
            fi

            echo "$CONFTEST_PREAMBLE
            #include <linux/mm.h>
            int conftest_remap_page_range(void) {
                pgprot_t pgprot = __pgprot(0);
                return remap_page_range(NULL, 0L, 0L, 0L, pgprot);
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                echo "#define NV_REMAP_PAGE_RANGE_PRESENT" >> conftest.h
                echo "#define NV_REMAP_PAGE_RANGE_ARGUMENT_COUNT 5" >> conftest.h
                rm -f conftest$$.o
                return
            fi

            echo "$CONFTEST_PREAMBLE
            #include <linux/mm.h>
            int conftest_remap_page_range(void) {
                pgprot_t pgprot = __pgprot(0);
                return remap_page_range(0L, 0L, 0L, pgprot);
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                echo "#define NV_REMAP_PAGE_RANGE_PRESENT" >> conftest.h
                echo "#define NV_REMAP_PAGE_RANGE_ARGUMENT_COUNT 4" >> conftest.h
                rm -f conftest$$.o
                return
            else
                echo "#error remap_page_range() conftest failed!" >> conftest.h
                return
            fi
        ;;

        set_memory_uc)
            #
            # Determine if the set_memory_uc() function is present.
            #
            CODE="
            #if defined(NV_ASM_SET_MEMORY_H_PRESENT)
            #include <asm/set_memory.h>
            #else
            #include <asm/cacheflush.h>
            #endif
            void conftest_set_memory_uc(void) {
                set_memory_uc();
            }"

            compile_check_conftest "$CODE" "NV_SET_MEMORY_UC_PRESENT" "" "functions"
        ;;

        set_memory_array_uc)
            #
            # Determine if the set_memory_array_uc() function is present.
            #
            CODE="
            #if defined(NV_ASM_SET_MEMORY_H_PRESENT)
            #include <asm/set_memory.h>
            #else
            #include <asm/cacheflush.h>
            #endif
            void conftest_set_memory_array_uc(void) {
                set_memory_array_uc();
            }"

            compile_check_conftest "$CODE" "NV_SET_MEMORY_ARRAY_UC_PRESENT" "" "functions"
        ;;

        set_pages_uc)
            #
            # Determine if the set_pages_uc() function is present.
            #
            CODE="
            #if defined(NV_ASM_SET_MEMORY_H_PRESENT)
            #include <asm/set_memory.h>
            #else
            #include <asm/cacheflush.h>
            #endif
            void conftest_set_pages_uc(void) {
                set_pages_uc();
            }"

        ;;

        outer_flush_all)
            #
            # Determine if the outer_cache_fns struct has flush_all member.
            #
            CODE="
            #include <asm/outercache.h>
            int conftest_outer_flush_all(void) {
                return offsetof(struct outer_cache_fns, flush_all);
            }"

            compile_check_conftest "$CODE" "NV_OUTER_FLUSH_ALL_PRESENT" "" "types"
        ;;

        change_page_attr)
            #
            # Determine if the change_page_attr() function is
            # present.
            #
            CODE="
            #include <linux/version.h>
            #include <linux/utsname.h>
            #include <linux/mm.h>
            #if LINUX_VERSION_CODE >= KERNEL_VERSION(2, 6, 0)
              #include <asm/cacheflush.h>
            #endif
            void conftest_change_page_attr(void) {
                change_page_attr();
            }"

            compile_check_conftest "$CODE" "NV_CHANGE_PAGE_ATTR_PRESENT" "" "functions"
        ;;

        pci_get_class)
            #
            # Determine if the pci_get_class() function is
            # present.
            #
            CODE="
            #include <linux/pci.h>
            void conftest_pci_get_class(void) {
                pci_get_class();
            }"

            compile_check_conftest "$CODE" "NV_PCI_GET_CLASS_PRESENT" "" "functions"
        ;;

        pci_get_domain_bus_and_slot)
            #
            # Determine if the pci_get_domain_bus_and_slot() function
            # is present.
            #
            CODE="
            #include <linux/pci.h>
            void conftest_pci_get_domain_bus_and_slot(void) {
                pci_get_domain_bus_and_slot();
            }"

            compile_check_conftest "$CODE" "NV_PCI_GET_DOMAIN_BUS_AND_SLOT_PRESENT" "" "functions"
        ;;

        remap_pfn_range)
            #
            # Determine if the remap_pfn_range() function is
            # present.
            #
            CODE="
            #include <linux/mm.h>
            void conftest_remap_pfn_range(void) {
                remap_pfn_range();
            }"

            compile_check_conftest "$CODE" "NV_REMAP_PFN_RANGE_PRESENT" "" "functions"
        ;;

        agp_backend_acquire)
            #
            # Determine if the agp_backend_acquire() function is
            # present and how many arguments it takes.
            #
            echo "$CONFTEST_PREAMBLE
            #include <linux/types.h>
            #include <linux/agp_backend.h>
            typedef struct agp_bridge_data agp_bridge_data;
            agp_bridge_data *conftest_agp_backend_acquire(struct pci_dev *dev) {
                return agp_backend_acquire(dev, 0L);
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                echo "#undef NV_AGP_BACKEND_ACQUIRE_PRESENT" >> conftest.h
                rm -f conftest$$.o
                return
            fi

            echo "$CONFTEST_PREAMBLE
            #include <linux/types.h>
            #include <linux/agp_backend.h>
            typedef struct agp_bridge_data agp_bridge_data;
            agp_bridge_data *conftest_agp_backend_acquire(struct pci_dev *dev) {
                return agp_backend_acquire(dev);
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                echo "#define NV_AGP_BACKEND_ACQUIRE_PRESENT" >> conftest.h
                echo "#define NV_AGP_BACKEND_ACQUIRE_ARGUMENT_COUNT 1" >> conftest.h
                rm -f conftest$$.o
                return
            fi

            echo "$CONFTEST_PREAMBLE
            #include <linux/types.h>
            #include <linux/agp_backend.h>
            typedef struct agp_bridge_data agp_bridge_data;
            agp_bridge_data *conftest_agp_backend_acquire(void) {
                return agp_backend_acquire();
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                echo "#define NV_AGP_BACKEND_ACQUIRE_PRESENT" >> conftest.h
                echo "#define NV_AGP_BACKEND_ACQUIRE_ARGUMENT_COUNT 0" >> conftest.h
                rm -f conftest$$.o
                return
            else
                echo "#error agp_backend_acquire() conftest failed!" >> conftest.h
                return
            fi
        ;;

        vmap)
            #
            # Determine if the vmap() function is present and how
            # many arguments it takes.
            #
            echo "$CONFTEST_PREAMBLE
            #include <linux/vmalloc.h>
            void conftest_vmap(void) {
                vmap();
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                echo "#undef NV_VMAP_PRESENT" >> conftest.h
                rm -f conftest$$.o
                return
            fi

            echo "$CONFTEST_PREAMBLE
            #include <linux/vmalloc.h>
            void *conftest_vmap(struct page **pages, int count) {
                return vmap(pages, count);
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                echo "#define NV_VMAP_PRESENT" >> conftest.h
                echo "#define NV_VMAP_ARGUMENT_COUNT 2" >> conftest.h
                rm -f conftest$$.o
                return
            fi

            echo "$CONFTEST_PREAMBLE
            #include <linux/vmalloc.h>
            #include <linux/mm.h>
            void *conftest_vmap(struct page **pages, int count) {
                return vmap(pages, count, 0, PAGE_KERNEL);
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                echo "#define NV_VMAP_PRESENT" >> conftest.h
                echo "#define NV_VMAP_ARGUMENT_COUNT 4" >> conftest.h
                rm -f conftest$$.o
                return
            else
                echo "#error vmap() conftest failed!" >> conftest.h
                return
            fi
        ;;

        i2c_adapter)
            #
            # Determine if the 'i2c_adapter' structure has inc_use()
            # and client_register() members.
            #
            CODE="
            #include <linux/i2c.h>
            int conftest_i2c_adapter(void) {
                return offsetof(struct i2c_adapter, inc_use);
            }"

            compile_check_conftest "$CODE" "NV_I2C_ADAPTER_HAS_INC_USE" "" "types"

            CODE="
            #include <linux/i2c.h>
            int conftest_i2c_adapter(void) {
                return offsetof(struct i2c_adapter, client_register);
            }"

            compile_check_conftest "$CODE" "NV_I2C_ADAPTER_HAS_CLIENT_REGISTER" "" "types"
        ;;

        pm_message_t)
            #
            # Determine if the 'pm_message_t' data type is present
            # and if it as an 'event' member.
            #
            echo "$CONFTEST_PREAMBLE
            #include <linux/pm.h>
            void conftest_pm_message_t(pm_message_t state) {
                pm_message_t *p = &state;
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                echo "#define NV_PM_MESSAGE_T_PRESENT" >> conftest.h
                rm -f conftest$$.o
            else
                echo "#undef NV_PM_MESSAGE_T_PRESENT" >> conftest.h
                echo "#undef NV_PM_MESSAGE_T_HAS_EVENT" >> conftest.h
                return
            fi

            echo "$CONFTEST_PREAMBLE
            #include <linux/pm.h>  
            int conftest_pm_message_t(void) {
                return offsetof(pm_message_t, event);
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                echo "#define NV_PM_MESSAGE_T_HAS_EVENT" >> conftest.h
                rm -f conftest$$.o
                return
            else
                echo "#undef NV_PM_MESSAGE_T_HAS_EVENT" >> conftest.h
                return
            fi
        ;;

        pci_choose_state)
            #
            # Determine if the pci_choose_state() function is
            # present.
            #
            CODE="
            #include <linux/pci.h>
            void conftest_pci_choose_state(void) {
                pci_choose_state();
            }"

            compile_check_conftest "$CODE" "NV_PCI_CHOOSE_STATE_PRESENT" "" "functions"
        ;;

        vm_insert_page)
            #
            # Determine if the vm_insert_page() function is
            # present.
            #
            CODE="
            #include <linux/mm.h>
            void conftest_vm_insert_page(void) {
                vm_insert_page();
            }"

            compile_check_conftest "$CODE" "NV_VM_INSERT_PAGE_PRESENT" "" "functions"
        ;;

        irq_handler_t)
            #
            # Determine if the 'irq_handler_t' type is present and
            # if it takes a 'struct ptregs *' argument.
            #
            echo "$CONFTEST_PREAMBLE
            #include <linux/interrupt.h>
            irq_handler_t conftest_isr;
            " > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ ! -f conftest$$.o ]; then
                echo "#undef NV_IRQ_HANDLER_T_PRESENT" >> conftest.h
                rm -f conftest$$.o
                return
            fi

            rm -f conftest$$.o

            echo "$CONFTEST_PREAMBLE
            #include <linux/interrupt.h>
            irq_handler_t conftest_isr;
            int conftest_irq_handler_t(int irq, void *arg) {
                return conftest_isr(irq, arg);
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                echo "#define NV_IRQ_HANDLER_T_PRESENT" >> conftest.h
                echo "#define NV_IRQ_HANDLER_T_ARGUMENT_COUNT 2" >> conftest.h
                rm -f conftest$$.o
                return
            fi

            echo "$CONFTEST_PREAMBLE
            #include <linux/interrupt.h>
            irq_handler_t conftest_isr;
            int conftest_irq_handler_t(int irq, void *arg, struct pt_regs *regs) {
                return conftest_isr(irq, arg, regs);
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                echo "#define NV_IRQ_HANDLER_T_PRESENT" >> conftest.h
                echo "#define NV_IRQ_HANDLER_T_ARGUMENT_COUNT 3" >> conftest.h
                rm -f conftest$$.o
                return
            else
                echo "#error irq_handler_t() conftest failed!" >> conftest.h
                return
            fi
        ;;

        acpi_device_ops)
            #
            # Determine if the 'acpi_device_ops' structure has
            # a match() member.
            #
            CODE="
            #include <linux/acpi.h>
            int conftest_acpi_device_ops(void) {
                return offsetof(struct acpi_device_ops, match);
            }"

            compile_check_conftest "$CODE" "NV_ACPI_DEVICE_OPS_HAS_MATCH" "" "types"
        ;;

        acpi_op_remove)
            #
            # Determine the number of arguments to pass to the
            # 'acpi_op_remove' routine.
            #

            echo "$CONFTEST_PREAMBLE
            #include <linux/acpi.h>

            acpi_op_remove conftest_op_remove_routine;

            int conftest_acpi_device_ops_remove(struct acpi_device *device) {
                return conftest_op_remove_routine(device);
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                rm -f conftest$$.o
                echo "#define NV_ACPI_DEVICE_OPS_REMOVE_ARGUMENT_COUNT 1"  >> conftest.h
                return
            fi

            CODE="
            #include <linux/acpi.h>

            acpi_op_remove conftest_op_remove_routine;

            int conftest_acpi_device_ops_remove(struct acpi_device *device, int type) {
                return conftest_op_remove_routine(device, type);
            }"

            compile_check_conftest "$CODE" "NV_ACPI_DEVICE_OPS_REMOVE_ARGUMENT_COUNT" "2" "types"
        ;;

        acpi_device_id)
            #
            # Determine if the 'acpi_device_id' structure has 
            # a 'driver_data' member.
            #
            CODE="
            #include <linux/acpi.h>
            int conftest_acpi_device_id(void) {
                return offsetof(struct acpi_device_id, driver_data);
            }"

            compile_check_conftest "$CODE" "NV_ACPI_DEVICE_ID_HAS_DRIVER_DATA" "" "types"
        ;;

        acquire_console_sem)
            #
            # Determine if the acquire_console_sem() function
            # is present.
            #
            CODE="
            #include <linux/console.h>
            void conftest_acquire_console_sem(void) {
                acquire_console_sem(NULL);
            }"

            compile_check_conftest "$CODE" "NV_ACQUIRE_CONSOLE_SEM_PRESENT" "" "functions"
        ;;

        console_lock)
            #
            # Determine if the console_lock() function is present.
            #
            CODE="
            #include <linux/console.h>
            void conftest_console_lock(void) {
                console_lock(NULL);
            }"

            compile_check_conftest "$CODE" "NV_CONSOLE_LOCK_PRESENT" "" "functions"
        ;;

        kmem_cache_create)
            #
            # Determine if the kmem_cache_create() function is
            # present and how many arguments it takes.
            #
            echo "$CONFTEST_PREAMBLE
            #include <linux/slab.h>
            void conftest_kmem_cache_create(void) {
                kmem_cache_create();
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                rm -f conftest$$.o
                echo "#undef NV_KMEM_CACHE_CREATE_PRESENT" >> conftest.h
                return
            fi

            echo "$CONFTEST_PREAMBLE
            #include <linux/slab.h>
            void conftest_kmem_cache_create(void) {
                kmem_cache_create(NULL, 0, 0, 0L, NULL, NULL);
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                rm -f conftest$$.o
                echo "#define NV_KMEM_CACHE_CREATE_PRESENT" >> conftest.h
                echo "#define NV_KMEM_CACHE_CREATE_ARGUMENT_COUNT 6" >> conftest.h
                return
            fi

            echo "$CONFTEST_PREAMBLE
            #include <linux/slab.h>
            void conftest_kmem_cache_create(void) {
                kmem_cache_create(NULL, 0, 0, 0L, NULL);
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                rm -f conftest$$.o
                echo "#define NV_KMEM_CACHE_CREATE_PRESENT" >> conftest.h
                echo "#define NV_KMEM_CACHE_CREATE_ARGUMENT_COUNT 5" >> conftest.h
                return
            else
                echo "#error kmem_cache_create() conftest failed!" >> conftest.h
            fi
        ;;

        smp_call_function)
            #
            # Determine if the smp_call_function() function is
            # present and how many arguments it takes.
            #
            echo "$CONFTEST_PREAMBLE
            #include <linux/smp.h>
            void conftest_smp_call_function(void) {
            #ifdef CONFIG_SMP
                smp_call_function();
            #endif
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                rm -f conftest$$.o
                echo "#undef NV_SMP_CALL_FUNCTION_PRESENT" >> conftest.h
                return
            fi

            echo "$CONFTEST_PREAMBLE
            #include <linux/smp.h>
            void conftest_smp_call_function(void) {
                smp_call_function(NULL, NULL, 0, 0);
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                rm -f conftest$$.o
                echo "#define NV_SMP_CALL_FUNCTION_PRESENT" >> conftest.h
                echo "#define NV_SMP_CALL_FUNCTION_ARGUMENT_COUNT 4" >> conftest.h
                return
            fi

            echo "$CONFTEST_PREAMBLE
            #include <linux/smp.h>
            void conftest_smp_call_function(void) {
                smp_call_function(NULL, NULL, 0);
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                rm -f conftest$$.o
                echo "#define NV_SMP_CALL_FUNCTION_PRESENT" >> conftest.h
                echo "#define NV_SMP_CALL_FUNCTION_ARGUMENT_COUNT 3" >> conftest.h
                return
            else
                echo "#error smp_call_function() conftest failed!" >> conftest.h
            fi
        ;;

        on_each_cpu)
            #
            # Determine if the on_each_cpu() function is present
            # and how many arguments it takes.
            #
            echo "$CONFTEST_PREAMBLE
            #include <linux/smp.h>
            void conftest_on_each_cpu(void) {
            #ifdef CONFIG_SMP
                on_each_cpu();
            #endif
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                rm -f conftest$$.o
                echo "#undef NV_ON_EACH_CPU_PRESENT" >> conftest.h
                return
            fi

            echo "$CONFTEST_PREAMBLE
            #include <linux/smp.h>
            void conftest_on_each_cpu(void) {
                on_each_cpu(NULL, NULL, 0, 0);
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                rm -f conftest$$.o
                echo "#define NV_ON_EACH_CPU_PRESENT" >> conftest.h
                echo "#define NV_ON_EACH_CPU_ARGUMENT_COUNT 4" >> conftest.h
                return
            fi

            echo "$CONFTEST_PREAMBLE
            #include <linux/smp.h>
            void conftest_on_each_cpu(void) {
                on_each_cpu(NULL, NULL, 0);
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                rm -f conftest$$.o
                echo "#define NV_ON_EACH_CPU_PRESENT" >> conftest.h
                echo "#define NV_ON_EACH_CPU_ARGUMENT_COUNT 3" >> conftest.h
                return
            else
                echo "#error on_each_cpu() conftest failed!" >> conftest.h
            fi
        ;;

        vmm_support)
            # check if a VMM is supported (Xen only for now).
            if [ -f nv-xen.h ]; then
                echo "#define HAVE_NV_XEN 1" >> conftest.h
                return
            else
                echo "#undef HAVE_NV_XEN" >> conftest.h
            fi
        ;;

        register_cpu_notifier)
            #
            # Determine if register_cpu_notifier() is present
            # 
            # register_cpu_notifier() was removed by the following commit
            #   2016 Dec 25: b272f732f888d4cf43c943a40c9aaa836f9b7431
            #
            CODE="
            #include <linux/cpu.h>
            void conftest_register_cpu_notifier(void) {
                register_cpu_notifier();
            }" > conftest$$.c
            compile_check_conftest "$CODE" "NV_REGISTER_CPU_NOTIFIER_PRESENT" "" "functions"
        ;;

        cpuhp_setup_state)
            #
            # Determine if cpuhp_setup_state() is present
            # 
            # cpuhp_setup_state() was added by the following commit
            #   2016 Feb 26: 5b7aa87e0482be768486e0c2277aa4122487eb9d 
            # 
            # It is used as a replacement for register_cpu_notifier
            CODE="
            #include <linux/cpu.h>
            void conftest_cpuhp_setup_state(void) {
                cpuhp_setup_state();
            }" > conftest$$.c
            compile_check_conftest "$CODE" "NV_CPUHP_SETUP_STATE_PRESENT" "" "functions"
        ;;

        acpi_evaluate_integer)
            #
            # Determine if the acpi_evaluate_integer() function is
            # present and the type of its 'data' argument.
            #

            echo "$CONFTEST_PREAMBLE
            #include <linux/acpi.h>
            acpi_status acpi_evaluate_integer(acpi_handle h, acpi_string s,
                struct acpi_object_list *l, unsigned long long *d) {
                return AE_OK;
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                rm -f conftest$$.o
                echo "#define NV_ACPI_EVALUATE_INTEGER_PRESENT" >> conftest.h
                echo "typedef unsigned long long nv_acpi_integer_t;" >> conftest.h
                return
            fi

            echo "$CONFTEST_PREAMBLE
            #include <linux/acpi.h>
            acpi_status acpi_evaluate_integer(acpi_handle h, acpi_string s,
                struct acpi_object_list *l, unsigned long *d) {
                return AE_OK;
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                rm -f conftest$$.o
                echo "#define NV_ACPI_EVALUATE_INTEGER_PRESENT" >> conftest.h
                echo "typedef unsigned long nv_acpi_integer_t;" >> conftest.h
                return
            else
                #
                # We can't report a compile test failure here because
                # this is a catch-all for both kernels that don't
                # have acpi_evaluate_integer() and kernels that have
                # broken header files that make it impossible to
                # tell if the function is present.
                #
                echo "#undef NV_ACPI_EVALUATE_INTEGER_PRESENT" >> conftest.h
                echo "typedef unsigned long nv_acpi_integer_t;" >> conftest.h
            fi
        ;;

        acpi_walk_namespace)
            #
            # Determine if the acpi_walk_namespace() function is present
            # and how many arguments it takes.
            #
            echo "$CONFTEST_PREAMBLE
            #include <linux/acpi.h>
            void conftest_acpi_walk_namespace(void) {
                acpi_walk_namespace();
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                rm -f conftest$$.o
                echo "#undef NV_ACPI_WALK_NAMESPACE_PRESENT" >> conftest.h
                return
            fi

            echo "$CONFTEST_PREAMBLE
            #include <linux/acpi.h>
            void conftest_acpi_walk_namespace(void) {
                acpi_walk_namespace(0, NULL, 0, NULL, NULL, NULL, NULL);
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                rm -f conftest$$.o
                echo "#define NV_ACPI_WALK_NAMESPACE_PRESENT" >> conftest.h
                echo "#define NV_ACPI_WALK_NAMESPACE_ARGUMENT_COUNT 7" >> conftest.h
                return
            fi

            echo "$CONFTEST_PREAMBLE
            #include <linux/acpi.h>
            void conftest_acpi_walk_namespace(void) {
                acpi_walk_namespace(0, NULL, 0, NULL, NULL, NULL);
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                rm -f conftest$$.o
                echo "#define NV_ACPI_WALK_NAMESPACE_PRESENT" >> conftest.h
                echo "#define NV_ACPI_WALK_NAMESPACE_ARGUMENT_COUNT 6" >> conftest.h
                return
            else
                echo "#error acpi_walk_namespace() conftest failed!" >> conftest.h
            fi
        ;;

        ioremap_cache)
            #
            # Determine if the ioremap_cache() function is present.
            #
            CODE="
            #include <asm/io.h>
            void conftest_ioremap_cache(void) {
                ioremap_cache();
            }"

            compile_check_conftest "$CODE" "NV_IOREMAP_CACHE_PRESENT" "" "functions"
        ;;

        ioremap_nocache)
            #
            # Determine if the ioremap_nocache() function is present.
            #
            # Removed by commit 4bdc0d676a64 ("remove ioremap_nocache and
            # devm_ioremap_nocache") in v5.6 (2020-01-06)
            #
            CODE="
            #include <asm/io.h>
            void conftest_ioremap_nocache(void) {
                ioremap_nocache();
            }"

            compile_check_conftest "$CODE" "NV_IOREMAP_NOCACHE_PRESENT" "" "functions"
        ;;

        ioremap_wc)
            #
            # Determine if the ioremap_wc() function is present.
            #
            CODE="
            #include <asm/io.h>
            void conftest_ioremap_wc(void) {
                ioremap_wc();
            }"

            compile_check_conftest "$CODE" "NV_IOREMAP_WC_PRESENT" "" "functions"
        ;;

        proc_dir_entry)
            #
            # Determine if the 'proc_dir_entry' structure has 
            # an 'owner' member.
            #
            CODE="
            #include <linux/proc_fs.h>
            int conftest_proc_dir_entry(void) {
                return offsetof(struct proc_dir_entry, owner);
            }"

            compile_check_conftest "$CODE" "NV_PROC_DIR_ENTRY_HAS_OWNER" "" "types"
        ;;

      INIT_WORK)
            #
            # Determine how many arguments the INIT_WORK() macro
            # takes.
            #
            echo "$CONFTEST_PREAMBLE
            #include <linux/workqueue.h>
            void conftest_INIT_WORK(void) {
                INIT_WORK();
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                echo "#undef NV_INIT_WORK_PRESENT" >> conftest.h
                rm -f conftest$$.o
                return
            fi

            echo "$CONFTEST_PREAMBLE
            #include <linux/workqueue.h>
            void conftest_INIT_WORK(void) {
                INIT_WORK((struct work_struct *)NULL, NULL, NULL);
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                echo "#define NV_INIT_WORK_PRESENT" >> conftest.h
                echo "#define NV_INIT_WORK_ARGUMENT_COUNT 3" >> conftest.h
                rm -f conftest$$.o
                return
            fi

            echo "$CONFTEST_PREAMBLE
            #include <linux/workqueue.h>
            void conftest_INIT_WORK(void) {
                INIT_WORK((struct work_struct *)NULL, NULL);
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                echo "#define NV_INIT_WORK_PRESENT" >> conftest.h
                echo "#define NV_INIT_WORK_ARGUMENT_COUNT 2" >> conftest.h
                rm -f conftest$$.o
                return
            else
                echo "#error INIT_WORK() conftest failed!" >> conftest.h
                return
            fi
        ;;

      pci_dma_mapping_error)
            #
            # Determine how many arguments pci_dma_mapping_error()
            # takes.
            #
            echo "$CONFTEST_PREAMBLE
            #include <linux/pci.h>
            int conftest_pci_dma_mapping_error(void) {
                return pci_dma_mapping_error(NULL, 0);
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                echo "#define NV_PCI_DMA_MAPPING_ERROR_PRESENT" >> conftest.h
                echo "#define NV_PCI_DMA_MAPPING_ERROR_ARGUMENT_COUNT 2" >> conftest.h
                rm -f conftest$$.o
                return
            fi

            echo "$CONFTEST_PREAMBLE
            #include <linux/pci.h>
            int conftest_pci_dma_mapping_error(void) {
                return pci_dma_mapping_error(0);
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                echo "#define NV_PCI_DMA_MAPPING_ERROR_PRESENT" >> conftest.h
                echo "#define NV_PCI_DMA_MAPPING_ERROR_ARGUMENT_COUNT 1" >> conftest.h
                rm -f conftest$$.o
                return
            else
                echo "#error pci_dma_mapping_error() conftest failed!" >> conftest.h
                return
            fi
        ;;

        agp_memory)
            #
            # Determine if the 'agp_memory' structure has
            # a 'pages' member.
            #
            echo "$CONFTEST_PREAMBLE
            #include <linux/types.h>
            #include <linux/agp_backend.h>
            int conftest_agp_memory(void) {
                return offsetof(struct agp_memory, pages);
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                echo "#define NV_AGP_MEMORY_HAS_PAGES" >> conftest.h
                rm -f conftest$$.o
                return
            else
                echo "#undef NV_AGP_MEMORY_HAS_PAGES" >> conftest.h
                return
            fi
        ;;

        scatterlist)
            #
            # Determine if the 'scatterlist' structure has
            # a 'page_link' member.
            #
            CODE="
            #include <linux/types.h>
            #include <linux/scatterlist.h>
            int conftest_scatterlist(void) {
                return offsetof(struct scatterlist, page_link);
            }"

            compile_check_conftest "$CODE" "NV_SCATTERLIST_HAS_PAGE_LINK" "" "types"
        ;;

        pci_domain_nr)
            #
            # Determine if the pci_domain_nr() function is present.
            #
            CODE="
            #include <linux/types.h>
            #include <linux/pci.h>
            int conftest_pci_domain_nr(struct pci_dev *dev) {
                return pci_domain_nr();
            }"

            compile_check_conftest "$CODE" "NV_PCI_DOMAIN_NR_PRESENT" "" "functions"
        ;;

        file_operations)
            #
            # Determine if the 'file_operations' structure has
            # 'ioctl', 'unlocked_ioctl' and 'compat_ioctl' fields.
            #
            CODE="
            #include <linux/fs.h>
            int conftest_file_operations(void) {
                return offsetof(struct file_operations, ioctl);
            }"

            compile_check_conftest "$CODE" "NV_FILE_OPERATIONS_HAS_IOCTL" "" "types"

            CODE="
            #include <linux/fs.h>
            int conftest_file_operations(void) {
                return offsetof(struct file_operations, unlocked_ioctl);
            }"

            compile_check_conftest "$CODE" "NV_FILE_OPERATIONS_HAS_UNLOCKED_IOCTL" "" "types"

            CODE="
            #include <linux/fs.h>
            int conftest_file_operations(void) {
                return offsetof(struct file_operations, compat_ioctl);
            }"

            compile_check_conftest "$CODE" "NV_FILE_OPERATIONS_HAS_COMPAT_IOCTL" "" "types"
        ;;

        proc_ops)
            CODE="
            #include <linux/proc_fs.h>
            int conftest_proc_ops(void) {
                return offsetof(struct proc_ops, proc_open);
            }"

            compile_check_conftest "$CODE" "NV_HAVE_PROC_OPS" "" "types"
        ;;

        sg_init_table)
            #
            # Determine if the sg_init_table() function is present.
            #
            echo "$CONFTEST_PREAMBLE
            #include <linux/scatterlist.h>
            void conftest_sg_init_table(struct scatterlist *sgl,
                    unsigned int nents) {
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ ! -f conftest$$.o ]; then
                echo "#undef NV_SG_INIT_TABLE_PRESENT" >> conftest.h
                return

            fi
            rm -f conftest$$.o

            echo "$CONFTEST_PREAMBLE
            #include <linux/types.h>
            #include <linux/scatterlist.h>
            void conftest_sg_init_table(struct scatterlist *sgl,
                    unsigned int nents) {
                sg_init_table();
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                echo "#undef NV_SG_INIT_TABLE_PRESENT" >> conftest.h
                rm -f conftest$$.o
                return
            else
                echo "#define NV_SG_INIT_TABLE_PRESENT" >> conftest.h
                return
            fi
        ;;

        efi_enabled)
            #
            # Determine if the efi_enabled symbol is present, or if
            # the efi_enabled() function is present and how many
            # arguments it takes.
            #
            echo "$CONFTEST_PREAMBLE
            #if defined(NV_LINUX_EFI_H_PRESENT)
            #include <linux/efi.h> 
            #endif
            int conftest_efi_enabled(void) {
                return efi_enabled();
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                echo "#undef NV_EFI_ENABLED_PRESENT" | append_conftest "symbols"
                echo "#undef NV_EFI_ENABLED_PRESENT" | append_conftest "functions"
                rm -f conftest$$.o
                return
            fi

            echo "$CONFTEST_PREAMBLE
            #if defined(NV_LINUX_EFI_H_PRESENT)
            #include <linux/efi.h> 
            #endif
            int conftest_efi_enabled(void) {
                return efi_enabled(0);
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                echo "#define NV_EFI_ENABLED_PRESENT" | append_conftest "functions"
                echo "#define NV_EFI_ENABLED_ARGUMENT_COUNT 1" | append_conftest "functions"
                rm -f conftest$$.o
                return
            else
                echo "#define NV_EFI_ENABLED_PRESENT" | append_conftest "symbols"
                return
            fi
        ;;

        proc_create_data)
            #
            # Determine if the proc_create_data() function is present.
            #
            CODE="
            #include <linux/proc_fs.h>
            void conftest_proc_create_data(void) {
                proc_create_data();
            }"

            compile_check_conftest "$CODE" "NV_PROC_CREATE_DATA_PRESENT" "" "functions"
        ;;


        pde_data)
            #
            # Determine if the PDE_DATA() function is present.
            #
            CODE="
            #include <linux/proc_fs.h>
            void conftest_PDE_DATA(void) {
                PDE_DATA();
            }"

            compile_check_conftest "$CODE" "NV_PDE_DATA_PRESENT" "" "functions"
        ;;

        proc_remove)
            #
            # Determine if the proc_remove() function is present.
            #
            CODE="
            #include <linux/proc_fs.h>
            void conftest_proc_remove(void) {
                proc_remove();
            }"

            compile_check_conftest "$CODE" "NV_PROC_REMOVE_PRESENT" "" "functions"
        ;;

        drm_available)
            #
            # Determine if the DRM subsystem is usable
            #
            CODE="
            #if defined(NV_DRM_DRMP_H_PRESENT)
            #include <drm/drmP.h>
            #else
            #include <drm/drm_drv.h>
            #include <drm/drm_prime.h>
            #endif
            #if !defined(CONFIG_DRM) && !defined(CONFIG_DRM_MODULE)
            #error DRM not enabled
            #endif
            void conftest_drm_available(void) {
                struct drm_driver drv;
                drv.gem_prime_pin = 0;
                drv.gem_prime_get_sg_table = 0;
                drv.gem_prime_vmap = 0;
                drv.gem_prime_vunmap = 0;
                (void)drm_gem_prime_import;
                (void)drm_gem_prime_export;
            }"

            compile_check_conftest "$CODE" "NV_DRM_AVAILABLE" "" "generic"
        ;;

        get_num_physpages)
            #
            # Determine if the get_num_physpages() function is
            # present.
            #
            CODE="
            #include <linux/mm.h>
            void conftest_get_num_physpages(void) {
                get_num_physpages(NULL);
            }"

            compile_check_conftest "$CODE" "NV_GET_NUM_PHYSPAGES_PRESENT" "" "functions"
        ;;

        proc_remove)
            #
            # Determine if the proc_remove() function is present.
            #
            CODE="
            #include <linux/proc_fs.h>
            void conftest_proc_remove(void) {
                proc_remove();
            }"

            compile_check_conftest "$CODE" "NV_PROC_REMOVE_PRESENT" "" "functions"
        ;;

        vm_operations_struct)
            #
            # Determine if the 'vm_operations_struct' structure has
            # 'fault' and 'access' fields.
            #
            CODE="
            #include <linux/mm.h>
            int conftest_vm_operations_struct(void) {
                return offsetof(struct vm_operations_struct, fault);
            }"

            compile_check_conftest "$CODE" "NV_VM_OPERATIONS_STRUCT_HAS_FAULT" "" "types"

            CODE="
            #include <linux/mm.h>
            int conftest_vm_operations_struct(void) {
                return offsetof(struct vm_operations_struct, access);
            }"

            compile_check_conftest "$CODE" "NV_VM_OPERATIONS_STRUCT_HAS_ACCESS" "" "types"
        ;;

        fault_flags)
            # Determine if the FAULT_FLAG_WRITE is defined
            CODE="
            #include <linux/mm.h>
            void conftest_fault_flags(void) {
                int flag = FAULT_FLAG_WRITE;
            }"

            compile_check_conftest "$CODE" "NV_FAULT_FLAG_PRESENT" "" "types"
        ;;

        atomic_long_type)
            # Determine if atomic_long_t and associated functions are defined
            # Added in 2.6.16 2006-01-06 d3cb487149bd706aa6aeb02042332a450978dc1c
            CODE="
            #include <asm/atomic.h>
            void conftest_atomic_long(void) {
                atomic_long_t data;
                atomic_long_read(&data);
                atomic_long_set(&data, 0);
                atomic_long_inc(&data);
            }"

            compile_check_conftest "$CODE" "NV_ATOMIC_LONG_PRESENT" "" "types"
        ;;

        atomic64_type)
            # Determine if atomic64_t and associated functions are defined
            CODE="
            #include <asm/atomic.h>
            void conftest_atomic64(void) {
                atomic64_t data;
                atomic64_read(&data);
                atomic64_set(&data, 0);
                atomic64_inc(&data);
            }"

            compile_check_conftest "$CODE" "NV_ATOMIC64_PRESENT" "" "types"
        ;;

        task_struct)
            #
            # Determine if the 'task_struct' structure has
            # a 'cred' field.
            #
            CODE="
            #include <linux/sched.h>
            int conftest_task_struct(void) {
                return offsetof(struct task_struct, cred);
            }"

            compile_check_conftest "$CODE" "NV_TASK_STRUCT_HAS_CRED" "" "types"
        ;;

        backing_dev_info)
            #
            # Determine if the 'address_space' structure has
            # a 'backing_dev_info' field.
            #
            CODE="
            #include <linux/fs.h>
            int conftest_backing_dev_info(void) {
                return offsetof(struct address_space, backing_dev_info);
            }"

            compile_check_conftest "$CODE" "NV_ADDRESS_SPACE_HAS_BACKING_DEV_INFO" "" "types"
        ;;

        address_space)
            #
            # Determine if the 'address_space' structure has
            # a 'tree_lock' field of type rwlock_t.
            #
            CODE="
            #include <linux/fs.h>
            int conftest_address_space(void) {
                struct address_space as;
                rwlock_init(&as.tree_lock);
                return offsetof(struct address_space, tree_lock);
            }"

            compile_check_conftest "$CODE" "NV_ADDRESS_SPACE_HAS_RWLOCK_TREE_LOCK" "" "types"
        ;;

        address_space_init_once)
            #
            # Determine if address_space_init_once is present.
            #
            CODE="
            #include <linux/fs.h>
            void conftest_address_space_init_once(void) {
                address_space_init_once();
            }"

            compile_check_conftest "$CODE" "NV_ADDRESS_SPACE_INIT_ONCE_PRESENT" "" "functions"
        ;;

        kbasename)
            #
            # Determine if the kbasename() function is present.
            #
            CODE="
            #include <linux/string.h>
            void conftest_kbasename(void) {
                kbasename();
            }"

            compile_check_conftest "$CODE" "NV_KBASENAME_PRESENT" "" "functions"
        ;;

        fatal_signal_pending)
            #
            # Determine if fatal_signal_pending is present.
            #
            CODE="
            #include <linux/sched.h>
            void conftest_fatal_signal_pending(void) {
                fatal_signal_pending();
            }"

            compile_check_conftest "$CODE" "NV_FATAL_SIGNAL_PENDING_PRESENT" "" "functions"
        ;;

        kuid_t)
            #
            # Determine if the 'kuid_t' type is present.
            #
            CODE="
            #include <linux/sched.h>
            kuid_t conftest_kuid_t;
            "

            compile_check_conftest "$CODE" "NV_KUID_T_PRESENT" "" "types"
        ;;

        proc_remove)
            #
            # Determine if the proc_remove() function is present.
            #
            CODE="
            #include <linux/proc_fs.h>
            void conftest_proc_remove(void) {
                proc_remove();
            }"

            compile_check_conftest "$CODE" "NV_PROC_REMOVE_PRESENT" "" "functions"
        ;;

        vm_operations_struct)
            #
            # Determine if the 'vm_operations_struct' structure has
            # 'fault' and 'access' fields.
            #
            CODE="
            #include <linux/mm.h>
            int conftest_vm_operations_struct(void) {
                return offsetof(struct vm_operations_struct, fault);
            }"

            compile_check_conftest "$CODE" "NV_VM_OPERATIONS_STRUCT_HAS_FAULT" "" "types"

            CODE="
            #include <linux/mm.h>
            int conftest_vm_operations_struct(void) {
                return offsetof(struct vm_operations_struct, access);
            }"

            compile_check_conftest "$CODE" "NV_VM_OPERATIONS_STRUCT_HAS_ACCESS" "" "types"
        ;;

        vm_fault_present)
            #
            # Determine if the 'vm_fault' structure is present. The earlier
            # name for this struct was fault_data, and it was renamed to
            # vm_fault by:
            #
            #  2007-07-19  d0217ac04ca6591841e5665f518e38064f4e65bd
            #
            CODE="
            #include <linux/mm.h>
            int conftest_vm_fault_present(void) {
                return offsetof(struct vm_fault, flags);
            }"

            compile_check_conftest "$CODE" "NV_VM_FAULT_PRESENT" "" "types"
        ;;

        vm_fault_has_address)
            #
            # Determine if the 'vm_fault' structure has an 'address', or a
            # 'virtual_address' field. The .virtual_address field was
            # effectively renamed to .address, by these two commits:
            #
            # struct vm_fault: .address was added by:
            #  2016-12-14  82b0f8c39a3869b6fd2a10e180a862248736ec6f
            #
            # struct vm_fault: .virtual_address was removed by:
            #  2016-12-14  1a29d85eb0f19b7d8271923d8917d7b4f5540b3e
            #
            CODE="
            #include <linux/mm.h>
            int conftest_vm_fault_has_address(void) {
                return offsetof(struct vm_fault, address);
            }"

            compile_check_conftest "$CODE" "NV_VM_FAULT_HAS_ADDRESS" "" "types"
        ;;

        fault_flags)
            # Determine if the FAULT_FLAG_WRITE is defined
            CODE="
            #include <linux/mm.h>
            void conftest_fault_flags(void) {
                int flag = FAULT_FLAG_WRITE;
            }"

            compile_check_conftest "$CODE" "NV_FAULT_FLAG_PRESENT" "" "types"
        ;;

        atomic_long_type)
            # Determine if atomic_long_t and associated functions are defined
            # Added in 2.6.16 2006-01-06 d3cb487149bd706aa6aeb02042332a450978dc1c
            CODE="
            #include <asm/atomic.h>
            void conftest_atomic_long(void) {
                atomic_long_t data;
                atomic_long_read(&data);
                atomic_long_set(&data, 0);
                atomic_long_inc(&data);
            }"

            compile_check_conftest "$CODE" "NV_ATOMIC_LONG_PRESENT" "" "types"
        ;;

        atomic64_type)
            # Determine if atomic64_t and associated functions are defined
            CODE="
            #include <asm/atomic.h>
            void conftest_atomic64(void) {
                atomic64_t data;
                atomic64_read(&data);
                atomic64_set(&data, 0);
                atomic64_inc(&data);
            }"

            compile_check_conftest "$CODE" "NV_ATOMIC64_PRESENT" "" "types"
        ;;

        task_struct)
            #
            # Determine if the 'task_struct' structure has
            # a 'cred' field.
            #
            CODE="
            #include <linux/sched.h>
            int conftest_task_struct(void) {
                return offsetof(struct task_struct, cred);
            }"

            compile_check_conftest "$CODE" "NV_TASK_STRUCT_HAS_CRED" "" "types"
        ;;

        backing_dev_info)
            #
            # Determine if the 'address_space' structure has
            # a 'backing_dev_info' field.
            #
            CODE="
            #include <linux/fs.h>
            int conftest_backing_dev_info(void) {
                return offsetof(struct address_space, backing_dev_info);
            }"

            compile_check_conftest "$CODE" "NV_ADDRESS_SPACE_HAS_BACKING_DEV_INFO" "" "types"
        ;;

        address_space)
            #
            # Determine if the 'address_space' structure has
            # a 'tree_lock' field of type rwlock_t.
            #
            CODE="
            #include <linux/fs.h>
            int conftest_address_space(void) {
                struct address_space as;
                rwlock_init(&as.tree_lock);
                return offsetof(struct address_space, tree_lock);
            }"

            compile_check_conftest "$CODE" "NV_ADDRESS_SPACE_HAS_RWLOCK_TREE_LOCK" "" "types"
        ;;

        address_space_init_once)
            #
            # Determine if address_space_init_once is present.
            #
            CODE="
            #include <linux/fs.h>
            void conftest_address_space_init_once(void) {
                address_space_init_once();
            }"

            compile_check_conftest "$CODE" "NV_ADDRESS_SPACE_INIT_ONCE_PRESENT" "" "functions"
        ;;

        kbasename)
            #
            # Determine if the kbasename() function is present.
            #
            CODE="
            #include <linux/string.h>
            void conftest_kbasename(void) {
                kbasename();
            }"

            compile_check_conftest "$CODE" "NV_KBASENAME_PRESENT" "" "functions"
        ;;

        fatal_signal_pending)
            #
            # Determine if fatal_signal_pending is present.
            #
            CODE="
            #if defined(NV_LINUX_SCHED_SIGNAL_H_PRESENT)
            #include <linux/sched/signal.h>
            #else
            #include <linux/sched.h>
            #endif
            void conftest_fatal_signal_pending(void) {
                fatal_signal_pending();
            }"

            compile_check_conftest "$CODE" "NV_FATAL_SIGNAL_PENDING_PRESENT" "" "functions"
        ;;

        kuid_t)
            #
            # Determine if the 'kuid_t' type is present.
            #
            CODE="
            #include <linux/sched.h>
            kuid_t conftest_kuid_t;
            "

            compile_check_conftest "$CODE" "NV_KUID_T_PRESENT" "" "types"
        ;;

        pm_vt_switch_required)
            #
            # Determine if the pm_vt_switch_required() function is present.
            #
            CODE="
            #include <linux/pm.h>
            void conftest_pm_vt_switch_required(void) {
                pm_vt_switch_required();
            }"

            compile_check_conftest "$CODE" "NV_PM_VT_SWITCH_REQUIRED_PRESENT" "" "functions"
        ;;

        file_inode)
            #
            # Determine if the 'file' structure has
            # a 'f_inode' field.
            #
            CODE="
            #include <linux/fs.h>
            int conftest_file_inode(void) {
                return offsetof(struct file, f_inode);
            }"

            compile_check_conftest "$CODE" "NV_FILE_HAS_INODE" "" "types"
        ;;

        drm_pci_set_busid)
            #
            # Determine if the drm_pci_set_busid function is present.
            #
            CODE="
            #if defined(NV_DRM_DRMP_H_PRESENT)
            #include <drm/drmP.h>
            #else
            #include <drm/drm_drv.h>
            #endif
            void conftest_drm_pci_set_busid(void) {
                drm_pci_set_busid();
            }"

            compile_check_conftest "$CODE" "NV_DRM_PCI_SET_BUSID_PRESENT" "" "functions"
        ;;

        write_cr4)
            #
            # Determine if the write_cr4() function is present.
            #
            CODE="
            #include <asm/processor.h>
            #if defined(NV_ASM_SYSTEM_H_PRESENT)
            #include <asm/system.h>
            #endif
            void conftest_write_cr4(void) {
                write_cr4();
            }"

            compile_check_conftest "$CODE" "NV_WRITE_CR4_PRESENT" "" "functions"
        ;;

        for_each_online_node)
            #
            # Determine if the for_each_online_node() function is present.
            #
            CODE="
            #include <linux/mm.h>
            void conftest_for_each_online_node() {
                for_each_online_node();
            }"

            compile_check_conftest "$CODE" "NV_FOR_EACH_ONLINE_NODE_PRESENT" "" "functions"
        ;;

        node_end_pfn)
            #
            # Determine if the node_end_pfn() function is present.
            #
            CODE="
            #include <linux/mm.h>
            void conftest_node_end_pfn() {
                node_end_pfn();
            }"

            compile_check_conftest "$CODE" "NV_NODE_END_PFN_PRESENT" "" "functions"
        ;;
        get_user_pages_remote)
            #
            # Determine if the function get_user_pages_remote() is
            # present and has write/force parameters.
            #
            # get_user_pages_remote() was added by:
            #   2016 Feb 12: 1e9877902dc7e11d2be038371c6fbf2dfcd469d7
            #
            # get_user_pages[_remote]() write/force parameters
            # replaced with gup_flags:
            #   2016 Oct 13: 768ae309a96103ed02eb1e111e838c87854d8b51
            #   2016 Oct 13: 9beae1ea89305a9667ceaab6d0bf46a045ad71e7
            #
            # get_user_pages_remote() added 'locked' parameter
            #   2016 Dec 14:5b56d49fc31dbb0487e14ead790fc81ca9fb2c99
            #
            # conftest #1: check if get_user_pages_remote() is available
            # return if not available.
            # Fall through to conftest #2 if it is present
            echo "$CONFTEST_PREAMBLE
            #include <linux/mm.h>
            int conftest_get_user_pages_remote(void) {
                get_user_pages_remote();
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                echo "#undef NV_GET_USER_PAGES_REMOTE_PRESENT" | append_conftest "functions"
                echo "#undef NV_GET_USER_PAGES_HAS_WRITE_AND_FORCE_ARGS" | append_conftest "functions"
                echo "#undef NV_GET_USER_PAGES_REMOTE_HAS_LOCKED_ARG" | append_conftest "functions"
                rm -f conftest$$.o
                return
            fi

            # conftest #2: check if get_user_pages() has write and
            # force arguments. Return if these arguments are present
            # Fall through to conftest #3 if these args are absent.
            echo "#define NV_GET_USER_PAGES_REMOTE_PRESENT" | append_conftest "functions"
            echo "$CONFTEST_PREAMBLE
            #include <linux/mm.h>
            long get_user_pages(unsigned long start,
                                unsigned long nr_pages,
                                int write,
                                int force,
                                struct page **pages,
                                struct vm_area_struct **vmas) {
                return 0;
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                echo "#define NV_GET_USER_PAGES_HAS_WRITE_AND_FORCE_ARGS" | append_conftest "functions"
                echo "#undef NV_GET_USER_PAGES_REMOTE_HAS_LOCKED_ARG" | append_conftest "functions"
                rm -f conftest$$.o
                return
            fi

            # conftest #3: check if get_user_pages_remote() has locked argument
            echo "#undef NV_GET_USER_PAGES_HAS_WRITE_AND_FORCE_ARGS" | append_conftest "functions"
            echo "$CONFTEST_PREAMBLE
            #include <linux/mm.h>
            long get_user_pages_remote(struct task_struct *tsk,
                                       struct mm_struct *mm,
                                       unsigned long start,
                                       unsigned long nr_pages,
                                       unsigned int gup_flags,
                                       struct page **pages,
                                       struct vm_area_struct **vmas,
                                       int *locked) {
                return 0;
            }" > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1
            rm -f conftest$$.c

            if [ -f conftest$$.o ]; then
                echo "#define NV_GET_USER_PAGES_REMOTE_HAS_LOCKED_ARG" | append_conftest "functions"
                rm -f conftest$$.o
            else
                echo "#undef NV_GET_USER_PAGES_REMOTE_HAS_LOCKED_ARG" | append_conftest "functions"
            fi
        ;;
        arch_phys_wc_add)
            #
            # Determine if the arch_phys_wc_add() function is present.
            # arch_phys_wc_add() was added by
            #   2013 May 13: d0d98eedee2178c803dd824bb09f52b0e2ac1811
            #   (Add arch_phys_wc_{add, del} to manipulate WC MTRRs if needed)
            #
            CODE="
            #include <asm/io.h>
            void conftest_arch_phys_wc_add() {
                arch_phys_wc_add();
            }"

            compile_check_conftest "$CODE" "NV_ARCH_PHYS_WC_ADD_PRESENT" "" "functions"
        ;;
        drm_driver_unload_has_int_return_type)
            #
            # Determine if drm_driver::unload() returns integer value, which has
            # been changed to void by commit -
            #
            #   2017-01-06  11b3c20bdd15d17382068be569740de1dccb173d
            #
            CODE="
            #if defined(NV_DRM_DRMP_H_PRESENT)
            #include <drm/drmP.h>
            #else
            #include <drm/drm_drv.h>
            #endif
            int conftest_drm_driver_unload_has_int_return_type(struct drm_driver *drv) {
                return drv->unload(NULL /* dev */);
            }"

            compile_check_conftest "$CODE" "NV_DRM_DRIVER_UNLOAD_HAS_INT_RETURN_TYPE" "" "types"
        ;;
    esac
}

build_cflags

case "$6" in
    cc_sanity_check)
        #
        # Check if the selected compiler can create object files
        # in the current environment.
        #
        VERBOSE=$7

        echo "int cc_sanity_check(void) {
            return 0;
        }" > conftest$$.c

        $CC -c conftest$$.c > /dev/null 2>&1
        rm -f conftest$$.c

        if [ ! -f conftest$$.o ]; then
            if [ "$VERBOSE" = "full_output" ]; then
                echo "";
            fi
            if [ "$CC" != "cc" ]; then
                echo "The C compiler '$CC' does not appear to be able to"
                echo "create object files.  Please make sure you have "
                echo "your Linux distribution's libc development package"
                echo "installed and that '$CC' is a valid C compiler";
                echo "name."
            else
                echo "The C compiler '$CC' does not appear to be able to"
                echo "create executables.  Please make sure you have "
                echo "your Linux distribution's gcc and libc development"
                echo "packages installed."
            fi
            if [ "$VERBOSE" = "full_output" ]; then
                echo "";
                echo "*** Failed CC sanity check. Bailing out! ***";
                echo "";
            fi
            exit 1
        else
            rm -f conftest$$.o
            exit 0
        fi
    ;;

    cc_version_check)
        #
        # Verify that the same compiler is used for the kernel and kernel
        # module.
        #
        VERBOSE=$7
        
        if [ ! -f gcc-version-check.c ]; then
          #
          # gcc-version-check.c is not in the current working directory.
          # This can happen when building the kernel module from an
          # NVIDIA-internal intermediate directory prior to creating an
          # NVIDIA driver package.  Since the version check below is less
          # useful than it used to be, just silently skip the test if
          # gcc-version-check.c is missing.
          #
          IGNORE_CC_MISMATCH=1
        fi

        if [ -n "$IGNORE_CC_MISMATCH" -o -n "$SYSSRC" -o -n "$SYSINCLUDE" ]; then
          #
          # The user chose to disable the CC version test (which may or
          # may not be wise) or is building the module for a kernel not
          # currently running, which renders the test meaningless.
          #
          exit 0
        fi

        rm -f gcc-version-check
        $HOSTCC gcc-version-check.c -o gcc-version-check > /dev/null 2>&1
        if [ ! -f gcc-version-check ]; then
            if [ "$CC" != "cc" ]; then
                MSG="Could not compile 'gcc-version-check.c'.  Please be "
                MSG="$MSG sure you have your Linux distribution's libc "
                MSG="$MSG development package installed and that '$CC' "
                MSG="$MSG is a valid C compiler name."
            else
                MSG="Could not compile 'gcc-version-check.c'.  Please be "
                MSG="$MSG sure you have your Linux distribution's gcc "
                MSG="$MSG and libc development packages installed."
            fi
            RET=1
        else
            PROC_VERSION="/proc/version"
            if [ -f $PROC_VERSION ]; then
                MSG=`./gcc-version-check "$(cat $PROC_VERSION)"`
                RET=$?
            else
                MSG="$PROC_VERSION does not exist."
                RET=1
            fi
            rm -f gcc-version-check
        fi

        if [ "$RET" != "0" ]; then
            #
            # The gcc version check failed
            #
            
            if [ "$VERBOSE" = "full_output" ]; then
                echo "";
                echo "gcc-version-check failed:";
                echo "";
                echo "$MSG" | fmt -w 52
                echo "";
                echo "If you know what you are doing and want to override";
                echo "the gcc version check, you can do so by setting the";
                echo "IGNORE_CC_MISMATCH environment variable to \"1\".";
                echo "";
                echo "In any other case, set the CC environment variable";
                echo "to the name of the compiler that was used to compile";
                echo "the kernel.";
                echo ""
                echo "*** Failed CC version check. Bailing out! ***";
                echo "";
            else
                echo "$MSG";
            fi
            exit 1;
        else
            exit 0
        fi
    ;;

    suser_sanity_check)
        #
        # Determine the caller's user id to determine if we have sufficient
        # privileges for the requested operation.
        #
        if [ $(id -ur) != 0 ]; then
            echo "";
            echo "Please run \"make install\" as root.";
            echo "";
            echo "*** Failed super-user sanity check. Bailing out! ***";
            exit 1
        else
            exit 0
        fi
    ;;

    rmmod_sanity_check)
        #
        # Make sure that any currently loaded NVIDIA kernel module can be
        # unloaded.
        #
        MODULE="nvidia"

        if [ -n "$SYSSRC" -o -n "$SYSINCLUDE" ]; then
          #
          # Don't attempt to remove the kernel module if we're not
          # building against the running kernel.
          #
          exit 0
        fi

        if lsmod | grep -wq $MODULE; then
          rmmod $MODULE > /dev/null 2>&1
        fi

        if lsmod | grep -wq $MODULE; then
            #
            # The NVIDIA kernel module is still loaded, most likely because
            # it is busy.
            #
            echo "";
            echo "Unable to remove existing NVIDIA kernel module.";
            echo "Please be sure you have exited X before attempting";
            echo "to install the NVIDIA kernel module.";
            echo "";
            echo "*** Failed rmmod sanity check. Bailing out! ***";
            exit 1
        else
            exit 0
        fi
    ;;

    select_makefile)
        #
        # Select which Makefile to use based on the version of the
        # kernel we are building against: use the kbuild Makefile for
        # 2.6 and newer kernels, and the old Makefile for kernels older
        # than 2.6.
        #
        rm -f Makefile
        RET=1
        VERBOSE=$7
        FILE="linux/version.h"
        SELECTED_MAKEFILE=""

        if [ -f $HEADERS/$FILE -o -f $OUTPUT/include/$FILE -o \
	     -f $OUTPUT/include/generated/uapi/$FILE ]; then
            #
            # We are either looking at a configured kernel source
            # tree or at headers shipped for a specific kernel.
            # Determine the kernel version using a compile check.
            #
            rm -f conftest.h
            test_headers

            echo "$CONFTEST_PREAMBLE
            #include <linux/version.h>
            #include <linux/utsname.h>
            #if defined(TEST_2_4) && (LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,0))
              #error \"!KERNEL_2_4\"
            #endif
            #if defined(TEST_2_6_OR_3) && (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,0))
              #error \"!KERNEL_2_6_OR_3\"
            #endif" > conftest$$.c

            $CC $CFLAGS -DTEST_2_6_OR_3 -c conftest$$.c > /dev/null 2>&1

            if [ -f conftest$$.o ]; then
                if [ -f Makefile.rmlite ]; then
                    SELECTED_MAKEFILE=Makefile.rmlite
                else
                    SELECTED_MAKEFILE=Makefile.kbuild
                fi
                RET=0
            else
                $CC $CFLAGS -DTEST_2_4 -c conftest$$.c > /dev/null 2>&1

                if [ -f conftest$$.o ]; then
                    SELECTED_MAKEFILE=Makefile.nvidia
                    RET=0
                fi
            fi

            rm -f conftest$$.c conftest$$.o
            rm -f conftest.h
        else
            MAKEFILE=$HEADERS/../Makefile
            CONFIG=$HEADERS/../.config

            if [ -f $MAKEFILE -a -f $CONFIG ]; then
                #
                # This source tree is not configured, but includes
                # a Makefile and a .config file. If this is a 2.6
                # kernel older than 2.6.6, that's all we require to
                # build the module.
                #
                PATCHLEVEL=$(grep "^PATCHLEVEL =" $MAKEFILE | cut -d " " -f 3)
                SUBLEVEL=$(grep "^SUBLEVEL =" $MAKEFILE | cut -d " " -f 3)

                if [ -n "$PATCHLEVEL" -a $PATCHLEVEL -ge 6 \
                        -a -n "$SUBLEVEL" -a $SUBLEVEL -le 5 ]; then
                    SELECTED_MAKEFILE=Makefile.kbuild
                    RET=0
                fi
            fi
        fi

        if [ "$RET" = "0" ]; then
            ln -s $SELECTED_MAKEFILE Makefile
            exit 0
        else
            echo "If you are using a Linux 2.4 kernel, please make sure";
            echo "you either have configured kernel sources matching your";
            echo "kernel or the correct set of kernel headers installed";
            echo "on your system.";
            echo "";
            echo "If you are using a Linux 2.6 kernel, please make sure";
            echo "you have configured kernel sources matching your kernel";
            echo "installed on your system. If you specified a separate";
            echo "output directory using either the \"KBUILD_OUTPUT\" or";
            echo "the \"O\" KBUILD parameter, make sure to specify this";
            echo "directory with the SYSOUT environment variable or with";
            echo "the equivalent nvidia-installer command line option.";
            echo "";
            echo "Depending on where and how the kernel sources (or the";
            echo "kernel headers) were installed, you may need to specify";
            echo "their location with the SYSSRC environment variable or";
            echo "the equivalent nvidia-installer command line option.";
            echo "";
            if [ "$VERBOSE" = "full_output" ]; then
                echo "*** Unable to determine the target kernel version. ***";
                echo "";
            fi
            exit 1
        fi
    ;;

    get_uname)
        #
        # Print UTS_RELEASE from the kernel sources, if the kernel header
        # file ../linux/version.h or ../linux/utsrelease.h exists. If
        # neither header file is found, but a Makefile is found, extract
        # PATCHLEVEL and SUBLEVEL, and use them to build the kernel
        # release name.
        #
        # If no source file is found, or if an error occurred, return the
        # output of `uname -r`.
        #
        RET=1
        DIRS="generated linux"
        FILE=""
        
        for DIR in $DIRS; do
            if [ -f $HEADERS/$DIR/utsrelease.h ]; then
                FILE="$HEADERS/$DIR/utsrelease.h"
                break
            elif [ -f $OUTPUT/include/$DIR/utsrelease.h ]; then
                FILE="$OUTPUT/include/$DIR/utsrelease.h"
                break
            fi
        done

        if [ -z "$FILE" ]; then
            if [ -f $HEADERS/linux/version.h ]; then
                FILE="$HEADERS/linux/version.h"
            elif [ -f $OUTPUT/include/linux/version.h ]; then
                FILE="$OUTPUT/include/linux/version.h"
            fi
        fi

        if [ -n "$FILE" ]; then
            #
            # We are either looking at a configured kernel source tree
            # or at headers shipped for a specific kernel.  Determine
            # the kernel version using a CPP check.
            #
            VERSION=`echo "UTS_RELEASE" | $CC - -E -P -include $FILE 2>&1`

            if [ "$?" = "0" -a "VERSION" != "UTS_RELEASE" ]; then
                echo "$VERSION"
                RET=0
            fi
        else
            #
            # If none of the kernel headers ar found, but a Makefile is,
            # extract PATCHLEVEL and SUBLEVEL and use them to find
            # the kernel version.
            #
            MAKEFILE=$HEADERS/../Makefile

            if [ -f $MAKEFILE ]; then
                #
                # This source tree is not configured, but includes
                # the top-level Makefile.
                #
                PATCHLEVEL=$(grep "^PATCHLEVEL =" $MAKEFILE | cut -d " " -f 3)
                SUBLEVEL=$(grep "^SUBLEVEL =" $MAKEFILE | cut -d " " -f 3)

                if [ -n "$PATCHLEVEL" -a -n "$SUBLEVEL" ]; then
                    echo 2.$PATCHLEVEL.$SUBLEVEL
                    RET=0
                fi
            fi
        fi

        if [ "$RET" != "0" ]; then
            uname -r
            exit 1
        else
            exit 0
        fi
    ;;

    rivafb_sanity_check)
        #
        # Check if the kernel was compiled with rivafb support. If so, then
        # exit, since the driver no longer works with rivafb.
        #
        RET=1
        VERBOSE=$7
        OLD_FILE="linux/autoconf.h"
        NEW_FILE="generated/autoconf.h"

        if [ -f $HEADERS/$NEW_FILE -o -f $OUTPUT/include/$NEW_FILE ]; then
            FILE=$NEW_FILE
        fi
        if [ -f $HEADERS/$OLD_FILE -o -f $OUTPUT/include/$OLD_FILE ]; then
            FILE=$OLD_FILE
        fi

        if [ -n "$FILE" ]; then
            #
            # We are looking at a configured source tree; verify
            # that its configuration doesn't include rivafb using
            # a compile check.
            #
            rm -f conftest.h
            test_headers

            echo "$CONFTEST_PREAMBLE
            #ifdef CONFIG_FB_RIVA
            #error CONFIG_FB_RIVA defined!
            #endif
            " > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1

            if [ -f conftest$$.o ]; then
                RET=0
            fi

            rm -f conftest$$.c conftest$$.o
            rm -f conftest.h
        else
            CONFIG=$HEADERS/../.config
            if [ -f $CONFIG ]; then
                if [ -z "$(grep "^CONFIG_FB_RIVA=y" $CONFIG)" ]; then
                    RET=0
                fi
            fi
        fi

        if [ "$RET" != "0" ]; then
            echo "Your kernel was configured to include rivafb support!";
            echo "";
            echo "The rivafb driver conflicts with the NVIDIA driver, please";
            echo "reconfigure your kernel and *disable* rivafb support, then";
            echo "try installing the NVIDIA kernel module again.";
            echo "";
            if [ "$VERBOSE" = "full_output" ]; then
                echo "*** Failed rivafb sanity check. Bailing out! ***";
                echo "";
            fi
            exit 1
        else
            exit 0
        fi
    ;;

    nvidiafb_sanity_check)
        #
        # Check if the kernel was compiled with nvidiafb support. If so, then
        # exit, since the driver doesn't work with nvidiafb.
        #
        RET=1
        VERBOSE=$7
        OLD_FILE="linux/autoconf.h"
        NEW_FILE="generated/autoconf.h"

        if [ -f $HEADERS/$NEW_FILE -o -f $OUTPUT/include/$NEW_FILE ]; then
            FILE=$NEW_FILE
        fi
        if [ -f $HEADERS/$OLD_FILE -o -f $OUTPUT/include/$OLD_FILE ]; then
            FILE=$OLD_FILE
        fi

        if [ -n "$FILE" ]; then
            #
            # We are looking at a configured source tree; verify
            # that its configuration doesn't include nvidiafb using
            # a compile check.
            #
            rm -f conftest.h
            test_headers

            echo "$CONFTEST_PREAMBLE
            #ifdef CONFIG_FB_NVIDIA
            #error CONFIG_FB_NVIDIA defined!
            #endif
            " > conftest$$.c

            $CC $CFLAGS -c conftest$$.c > /dev/null 2>&1

            if [ -f conftest$$.o ]; then
                RET=0
            fi

            rm -f conftest$$.c conftest$$.o
            rm -f conftest.h
        else
            CONFIG=$HEADERS/../.config
            if [ -f $CONFIG ]; then
                if [ -z "$(grep "^CONFIG_FB_NVIDIA=y" $CONFIG)" ]; then
                    RET=0
                fi
            fi
        fi

        if [ "$RET" != "0" ]; then
            echo "Your kernel was configured to include nvidiafb support!";
            echo "";
            echo "The nvidiafb driver conflicts with the NVIDIA driver, please";
            echo "reconfigure your kernel and *disable* nvidiafb support, then";
            echo "try installing the NVIDIA kernel module again.";
            echo "";
            if [ "$VERBOSE" = "full_output" ]; then
                echo "*** Failed nvidiafb sanity check. Bailing out! ***";
                echo "";
            fi
            exit 1
        else
            exit 0
        fi
    ;;

    xen_sanity_check)
        #
        # Check if the target kernel is a Xen kernel. If so, then exit, since
        # the driver doesn't currently work with Xen.
        #
        VERBOSE=$7

        if [ -n "$IGNORE_XEN_PRESENCE" ]; then
            exit 0
        fi

        if [ "$XEN_PRESENT" != "0" ]; then
            echo "The kernel you are installing for is a Xen kernel!";
            echo "";
            echo "The NVIDIA driver does not currently work on Xen kernels. If ";
            echo "you are using a stock distribution kernel, please install ";
            echo "a variant of this kernel without Xen support; if this is a ";
            echo "custom kernel, please install a standard Linux kernel.  Then ";
            echo "try installing the NVIDIA kernel module again.";
            echo "";
            if [ "$VERBOSE" = "full_output" ]; then
                echo "*** Failed Xen sanity check. Bailing out! ***";
                echo "";
            fi
            exit 1
        else
            exit 0
        fi
    ;;

    patch_check)
        #
        # Check for any "official" patches that may have been applied and
        # construct a description table for reporting purposes.
        #
        PATCHES=""

        for PATCH in patch-*.h; do
            if [ -f $PATCH ]; then
                echo "#include \"$PATCH\"" >> patches.h
                PATCHES="$PATCHES "`echo $PATCH | sed -s 's/patch-\(.*\)\.h/\1/'`
            fi
        done

        echo "static struct {
                const char *short_description;
                const char *description;
              } __nv_patches[] = {" >> patches.h
            for i in $PATCHES; do
                echo "{ \"$i\", NV_PATCH_${i}_DESCRIPTION }," >> patches.h
            done
        echo "{ NULL, NULL } };" >> patches.h

        exit 0
    ;;

    compile_tests)
        #
        # Run a series of compile tests to determine the set of interfaces
        # and features available in the target kernel.
        #
        shift 5

        rm -f conftest.h
        test_headers

        for i in $*; do compile_test $i; done

        if [ -n "$SHOW_COMPILE_TEST_RESULTS" -a -f conftest.h ]; then
            cat conftest.h
        fi

        exit 0
    ;;

esac
