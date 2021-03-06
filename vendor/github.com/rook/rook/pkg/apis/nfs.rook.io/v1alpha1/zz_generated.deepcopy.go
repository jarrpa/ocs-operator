// +build !ignore_autogenerated

/*
Copyright The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

// Code generated by deepcopy-gen. DO NOT EDIT.

package v1alpha1

import (
	v1 "github.com/rook/rook/pkg/apis/rook.io/v1"
	runtime "k8s.io/apimachinery/pkg/runtime"
)

// DeepCopyInto is an autogenerated deepcopy function, copying the receiver, writing into out. in must be non-nil.
func (in *AllowedClientsSpec) DeepCopyInto(out *AllowedClientsSpec) {
	*out = *in
	if in.Clients != nil {
		in, out := &in.Clients, &out.Clients
		*out = make([]string, len(*in))
		copy(*out, *in)
	}
	return
}

// DeepCopy is an autogenerated deepcopy function, copying the receiver, creating a new AllowedClientsSpec.
func (in *AllowedClientsSpec) DeepCopy() *AllowedClientsSpec {
	if in == nil {
		return nil
	}
	out := new(AllowedClientsSpec)
	in.DeepCopyInto(out)
	return out
}

// DeepCopyInto is an autogenerated deepcopy function, copying the receiver, writing into out. in must be non-nil.
func (in *ExportsSpec) DeepCopyInto(out *ExportsSpec) {
	*out = *in
	in.Server.DeepCopyInto(&out.Server)
	out.PersistentVolumeClaim = in.PersistentVolumeClaim
	return
}

// DeepCopy is an autogenerated deepcopy function, copying the receiver, creating a new ExportsSpec.
func (in *ExportsSpec) DeepCopy() *ExportsSpec {
	if in == nil {
		return nil
	}
	out := new(ExportsSpec)
	in.DeepCopyInto(out)
	return out
}

// DeepCopyInto is an autogenerated deepcopy function, copying the receiver, writing into out. in must be non-nil.
func (in *NFSServer) DeepCopyInto(out *NFSServer) {
	*out = *in
	out.TypeMeta = in.TypeMeta
	in.ObjectMeta.DeepCopyInto(&out.ObjectMeta)
	in.Spec.DeepCopyInto(&out.Spec)
	out.Status = in.Status
	return
}

// DeepCopy is an autogenerated deepcopy function, copying the receiver, creating a new NFSServer.
func (in *NFSServer) DeepCopy() *NFSServer {
	if in == nil {
		return nil
	}
	out := new(NFSServer)
	in.DeepCopyInto(out)
	return out
}

// DeepCopyObject is an autogenerated deepcopy function, copying the receiver, creating a new runtime.Object.
func (in *NFSServer) DeepCopyObject() runtime.Object {
	if c := in.DeepCopy(); c != nil {
		return c
	}
	return nil
}

// DeepCopyInto is an autogenerated deepcopy function, copying the receiver, writing into out. in must be non-nil.
func (in *NFSServerList) DeepCopyInto(out *NFSServerList) {
	*out = *in
	out.TypeMeta = in.TypeMeta
	in.ListMeta.DeepCopyInto(&out.ListMeta)
	if in.Items != nil {
		in, out := &in.Items, &out.Items
		*out = make([]NFSServer, len(*in))
		for i := range *in {
			(*in)[i].DeepCopyInto(&(*out)[i])
		}
	}
	return
}

// DeepCopy is an autogenerated deepcopy function, copying the receiver, creating a new NFSServerList.
func (in *NFSServerList) DeepCopy() *NFSServerList {
	if in == nil {
		return nil
	}
	out := new(NFSServerList)
	in.DeepCopyInto(out)
	return out
}

// DeepCopyObject is an autogenerated deepcopy function, copying the receiver, creating a new runtime.Object.
func (in *NFSServerList) DeepCopyObject() runtime.Object {
	if c := in.DeepCopy(); c != nil {
		return c
	}
	return nil
}

// DeepCopyInto is an autogenerated deepcopy function, copying the receiver, writing into out. in must be non-nil.
func (in *NFSServerSpec) DeepCopyInto(out *NFSServerSpec) {
	*out = *in
	if in.Annotations != nil {
		in, out := &in.Annotations, &out.Annotations
		*out = make(v1.Annotations, len(*in))
		for key, val := range *in {
			(*out)[key] = val
		}
	}
	if in.Exports != nil {
		in, out := &in.Exports, &out.Exports
		*out = make([]ExportsSpec, len(*in))
		for i := range *in {
			(*in)[i].DeepCopyInto(&(*out)[i])
		}
	}
	return
}

// DeepCopy is an autogenerated deepcopy function, copying the receiver, creating a new NFSServerSpec.
func (in *NFSServerSpec) DeepCopy() *NFSServerSpec {
	if in == nil {
		return nil
	}
	out := new(NFSServerSpec)
	in.DeepCopyInto(out)
	return out
}

// DeepCopyInto is an autogenerated deepcopy function, copying the receiver, writing into out. in must be non-nil.
func (in *NFSServerStatus) DeepCopyInto(out *NFSServerStatus) {
	*out = *in
	return
}

// DeepCopy is an autogenerated deepcopy function, copying the receiver, creating a new NFSServerStatus.
func (in *NFSServerStatus) DeepCopy() *NFSServerStatus {
	if in == nil {
		return nil
	}
	out := new(NFSServerStatus)
	in.DeepCopyInto(out)
	return out
}

// DeepCopyInto is an autogenerated deepcopy function, copying the receiver, writing into out. in must be non-nil.
func (in *ServerSpec) DeepCopyInto(out *ServerSpec) {
	*out = *in
	if in.AllowedClients != nil {
		in, out := &in.AllowedClients, &out.AllowedClients
		*out = make([]AllowedClientsSpec, len(*in))
		for i := range *in {
			(*in)[i].DeepCopyInto(&(*out)[i])
		}
	}
	return
}

// DeepCopy is an autogenerated deepcopy function, copying the receiver, creating a new ServerSpec.
func (in *ServerSpec) DeepCopy() *ServerSpec {
	if in == nil {
		return nil
	}
	out := new(ServerSpec)
	in.DeepCopyInto(out)
	return out
}
