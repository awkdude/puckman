package dialog

import "../platform"
import win "core:sys/windows"
import "core:log"


open :: proc(
    start_dir: string,
    filters: []Filter, 
    flags: bit_set[OFD_Opts] = {},
    allocator := context.temp_allocator) -> (OFD, bool) 
{
// {{{
    res: win.HRESULT 
    open_file_dialog: ^win.IFileOpenDialog
    shell_item_array: ^win.IShellItemArray
    ofd_result: OFD

    // This can be called multiple times
    win.CoInitialize()
    res = win.CoCreateInstance(win.CLSID_FileOpenDialog, nil, win.CLSCTX_ALL, 
        win.IID_IFileOpenDialog, cast(^rawptr)&open_file_dialog)
    defer if win.SUCCEEDED(res) do open_file_dialog->Release()
    if !win.SUCCEEDED(res) do return ofd_result, false
    fos: u32
    if .Multiple_Files in flags {
        fos |= win.FOS_ALLOWMULTISELECT
    }
    if .Directories_Only in flags {
        fos |= win.FOS_PICKFOLDERS
    }
    open_file_dialog->SetOptions(fos)
    if start_dir != "" {
        item: win.IShellItem
        // TODO: Set start directory
        open_file_dialog->SetDefaultFolder(&item)
    }
    default_title :=  "Select a Folder" if .Directories_Only in flags else "Select a File"
    open_file_dialog->SetTitle(raw_data(platform.clone_to_wide_string(default_title)))

    filter_spec_array := make([]win.COMDLG_FILTERSPEC, len(filters), allocator)
    for filter, i in filters {
        filter_spec_array[i] = {
            pszName=raw_data(platform.clone_to_wide_string(filter.name)),
            pszSpec=raw_data(platform.clone_to_wide_string(filter.pattern)),
        }
    }
    open_file_dialog->SetFileTypes(cast(win.UINT)len(filters), raw_data(filter_spec_array))
    res = open_file_dialog->Show(nil)
    res = open_file_dialog->GetResults(&shell_item_array);
    if !win.SUCCEEDED(res) do return ofd_result, false
    num_items: win.DWORD
    shell_item_array->GetCount(&num_items)
    if num_items == 0 do return ofd_result, false
    ofd_result.paths = make([]string, num_items)

    for i in 0..<num_items {
        item: ^win.IShellItem
        name: ^u16
        shell_item_array->GetItemAt(i, &item)
        item->GetDisplayName(.FILESYSPATH, &name)
        ofd_result.paths[i] = transmute(string)platform.wide_to_cstring(name)
    }
    return ofd_result, true
// }}}
}
